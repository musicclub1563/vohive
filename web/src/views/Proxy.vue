<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import PageHeader from '../components/PageHeader.vue'
import EmptyState from '../components/EmptyState.vue'
import ListSkeleton from '../components/ListSkeleton.vue'
import ErrorState from '../components/ErrorState.vue'
import { usePollingScheduler } from '../composables/usePollingScheduler'
import { useUpstreamProxyStore } from '../stores/upstream-proxy'
import type { UpstreamProxy, UpstreamProxyCountry } from '../types/api'
import { toAppError } from '../services/http'
import {
  upstreamProxyAddressWarning,
  upstreamProxyIPv6AddressHint
} from '../utils/upstreamProxyAddress'
import {
  Add24Regular,
  Edit24Regular,
  Delete24Regular,
  Link24Regular,
  Earth24Regular
} from '@vicons/fluent'

// ── Tab 控制 ──
const activeTab = ref('upstream') // 默认展示前置代理

// ══════════════════════════════════════════════════════
// 前置代理（漫游前置代理）
// ══════════════════════════════════════════════════════
const upstreamStore = useUpstreamProxyStore()

const upstreamLoading = ref(true)
const upstreamRefreshing = ref(false)
const upstreamError = ref<{ message: string; status?: number } | null>(null)

// ── 编辑 Drawer ──
const upstreamDrawerOpen = ref(false)
const editingUpstream = ref<UpstreamProxy | null>(null)
const upstreamForm = ref<UpstreamProxy>({
  id: '',
  name: '',
  addr: '',
  username: '',
  password: '',
  enabled: true
})

// ── 国家规则管理 Drawer ──
const countryRuleDrawerOpen = ref(false)
const countryRuleTargetProxy = ref<UpstreamProxy | null>(null)
const selectedCountryCode = ref('')

const availableCountries = computed(() => {
  if (!countryRuleTargetProxy.value) return []
  return upstreamStore.countries.filter((country) => {
    const rule = upstreamStore.getRuleForCountry(country.country_code)
    return !rule || rule.upstream_proxy_id === countryRuleTargetProxy.value!.id
  })
})

const currentProxyCountryRules = computed(() => {
  if (!countryRuleTargetProxy.value) return []
  return upstreamStore.getRulesForProxy(countryRuleTargetProxy.value.id)
})

// 前置代理列表（带国家规则数量）
const upstreamProxiesWithRuleCount = computed(() => {
  return upstreamStore.proxies.map(p => ({
    ...p,
    ruleCount: upstreamStore.getRulesForProxy(p.id).length
  }))
})

async function fetchUpstream(opts: { silent?: boolean; initial?: boolean } = {}) {
  const isInitial = opts.initial === true
  const silent = opts.silent === true
  if (isInitial) {
    upstreamLoading.value = true
  } else if (!silent) {
    upstreamRefreshing.value = true
  }
  upstreamError.value = null

  try {
    const result = await upstreamStore.fetchAll()
    if (!result.ok) throw new Error(result.error.message)
  } catch (e: unknown) {
    const err = toAppError(e)
    upstreamError.value = {
      message: err.message || '加载前置代理失败',
      status: err.status
    }
  } finally {
    if (isInitial) {
      upstreamLoading.value = false
    } else if (!silent) {
      upstreamRefreshing.value = false
    }
  }
}

function openUpstreamDrawer(proxy?: UpstreamProxy) {
  if (!proxy) {
    editingUpstream.value = null
    upstreamForm.value = {
      id: '',
      name: '',
      addr: '',
      username: '',
      password: '',
      enabled: true
    }
  } else {
    editingUpstream.value = proxy
    upstreamForm.value = { ...proxy }
    // 密码脱敏时清空，让用户重新输入
    if (upstreamForm.value.password === '****') {
      upstreamForm.value.password = ''
    }
  }
  upstreamDrawerOpen.value = true
}

async function saveUpstreamForm() {
  const form = { ...upstreamForm.value }
  form.id = (form.id || '').trim()
  form.name = (form.name || '').trim()
  form.addr = (form.addr || '').trim()

  if (!form.id) {
    ElMessage.warning('ID 不能为空')
    return
  }
  if (!form.addr) {
    ElMessage.warning('Socks5 地址不能为空')
    return
  }
  const addrWarning = upstreamProxyAddressWarning(form.addr)
  if (addrWarning) {
    ElMessage.warning(addrWarning)
    return
  }

  try {
    if (editingUpstream.value) {
      // 更新
      const result = await upstreamStore.updateProxy(form.id, form)
      if (!result.ok) throw new Error(result.error.message || '更新失败')
      ElMessage.success('前置代理已更新，并通过连通性探测')
    } else {
      // 新增
      const result = await upstreamStore.createProxy(form)
      if (!result.ok) throw new Error(result.error.message || '创建失败')
      ElMessage.success('前置代理已创建，并通过连通性探测')
    }
    upstreamDrawerOpen.value = false
    await fetchUpstream()
  } catch (e: unknown) {
    const err = toAppError(e)
    ElMessage.error(err.message || '保存失败')
  }
}

async function deleteUpstream(proxy: UpstreamProxy) {
  const confirmed = await ElMessageBox.confirm(
    `确定删除前置代理「${proxy.name || proxy.id}」？\n绑定到该代理的国家规则将自动删除，相关国家会恢复直连。`,
    '确认删除',
    { confirmButtonText: '删除', cancelButtonText: '取消', type: 'warning' }
  ).then(() => true).catch(() => false)

  if (!confirmed) return

  try {
    const result = await upstreamStore.deleteProxy(proxy.id)
    if (!result.ok) throw new Error(result.error.message || '删除失败')
    ElMessage.success('前置代理已删除')
    await fetchUpstream()
  } catch (e: unknown) {
    const err = toAppError(e)
    ElMessage.error(err.message || '删除失败')
  }
}

function openCountryRuleDrawer(proxy: UpstreamProxy) {
  countryRuleTargetProxy.value = proxy
  selectedCountryCode.value = ''
  countryRuleDrawerOpen.value = true
}

async function doUpsertCountryRule() {
  if (!countryRuleTargetProxy.value || !selectedCountryCode.value) {
    ElMessage.warning('请选择国家')
    return
  }

  try {
    const result = await upstreamStore.upsertCountryRule(selectedCountryCode.value, {
      upstream_proxy_id: countryRuleTargetProxy.value.id,
      enabled: true
    })
    if (!result.ok) throw new Error(result.error.message || '保存规则失败')
    ElMessage.success('国家规则已保存')
    selectedCountryCode.value = ''
    await fetchUpstream()
  } catch (e: unknown) {
    const err = toAppError(e)
    ElMessage.error(err.message || '保存规则失败')
  }
}

async function doDeleteCountryRule(countryCode: string) {
  try {
    const result = await upstreamStore.deleteCountryRule(countryCode)
    if (!result.ok) throw new Error(result.error.message || '删除规则失败')
    ElMessage.success('国家规则已删除，该国家将默认直连')
    await fetchUpstream()
  } catch (e: unknown) {
    const err = toAppError(e)
    ElMessage.error(err.message || '删除规则失败')
  }
}

function formatCountryLabel(country: UpstreamProxyCountry): string {
  const name = country.country_name || country.country_code
  const mccs = country.mccs?.length ? ` · MCC ${country.mccs.join('/')}` : ''
  return `${country.country_code} · ${name}${mccs}`
}

// ── 统一初始化 ──
onMounted(() => {
  fetchUpstream({ initial: true })
})

// 前置代理轮询
const upPollEnabled = computed(() => !upstreamLoading.value && activeTab.value === 'upstream')
usePollingScheduler(() => fetchUpstream({ silent: true }), 10000, {
  enabled: upPollEnabled,
  maxIntervalMs: 60000,
  backgroundIntervalMs: 30000
})
</script>

<template>
  <div class="max-w-7xl mx-auto">
    <PageHeader title="代理管理" subtitle="管理 VoWiFi 漫游前置代理" />

    <!-- Tab 切换 -->
    <el-tabs v-model="activeTab" class="proxy-tabs mb-4">
      <el-tab-pane name="upstream">
        <template #label>
          <div class="flex items-center gap-1.5">
            <el-icon size="16"><Earth24Regular /></el-icon>
            <span class="font-medium">漫游前置代理</span>
            <span v-if="upstreamStore.proxies.length > 0" class="inline-flex items-center justify-center px-1.5 py-0.5 text-[10px] font-bold leading-none text-white bg-blue-500 rounded-full shadow-sm ml-0.5">
              {{ upstreamStore.proxies.length }}
            </span>
          </div>
        </template>
      </el-tab-pane>
      
    </el-tabs>

    <!-- ═══════════ 前置代理 Tab ═══════════ -->
    <div v-show="activeTab === 'upstream'">
      <ErrorState
        v-if="upstreamError"
        class="mb-6"
        title="加载前置代理失败"
        :message="upstreamError.message"
        :status-code="upstreamError.status"
        retry-text="重试"
        @retry="fetchUpstream"
      />

      <div class="ui-card p-6">
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-xl bg-gradient-to-br from-violet-500 to-fuchsia-500 text-white flex items-center justify-center shadow-lg shadow-violet-500/25">
              <el-icon size="20"><Earth24Regular /></el-icon>
            </div>
            <div>
              <div class="text-lg font-bold text-gray-900 dark:text-white">VoWiFi 漫游前置代理</div>
              <div class="text-xs text-gray-500">VoWiFi 通过 Socks5 代理穿透连接海外运营商。注意 Socks5 端必须支持 UDP Associate</div>
            </div>
          </div>
          <el-button type="primary" @click="openUpstreamDrawer()" class="!border-0">
            <el-icon class="mr-1.5"><Add24Regular /></el-icon>
            <span>新增代理</span>
          </el-button>
        </div>

        <ListSkeleton v-if="upstreamLoading && upstreamStore.proxies.length === 0" :rows="2" />

        <EmptyState
          v-else-if="upstreamStore.proxies.length === 0"
          title="暂无前置代理"
          subtitle="点击「新增代理」创建 Socks5 前置代理，再按国家配置 VoWiFi 分流规则；未配置国家默认直连"
        />

        <div v-else class="space-y-3">
          <div
            v-for="proxy in upstreamProxiesWithRuleCount"
            :key="proxy.id"
            class="ui-panel-muted p-4 flex flex-col lg:flex-row lg:items-center lg:justify-between gap-3"
          >
            <div class="flex items-center gap-3 min-w-0">
              <span class="w-2.5 h-2.5 rounded-full shrink-0" :class="proxy.enabled ? 'bg-green-500' : 'bg-gray-300'" />
              <div class="min-w-0">
                <div class="font-bold text-gray-900 dark:text-white truncate">{{ proxy.name || proxy.id }}</div>
                <div class="text-xs text-gray-500 mt-0.5 truncate">
                  Socks5 · <span class="font-mono">{{ proxy.addr }}</span>
                  <span v-if="proxy.username"> · 鉴权: {{ proxy.username }}</span>
                </div>
              </div>
            </div>

            <div class="flex items-center gap-2 shrink-0 flex-wrap">
              <el-tag size="small" :type="proxy.enabled ? 'success' : 'info'">
                {{ proxy.enabled ? '已启用' : '已禁用' }}
              </el-tag>
              
              <div class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[11px] font-medium bg-blue-50 text-blue-600 border border-blue-200/60 dark:bg-blue-900/20 dark:text-blue-400 dark:border-blue-800/40">
                <el-icon size="14"><Link24Regular /></el-icon>
                <span>{{ proxy.ruleCount }} 个国家规则</span>
              </div>

              <div class="w-px h-3.5 bg-gray-200 dark:bg-gray-700 mx-0.5 hidden sm:block"></div>

              <el-button size="small" @click="openCountryRuleDrawer(proxy)">
                <div class="flex items-center gap-1 -my-0.5">
                  <el-icon size="14"><Link24Regular /></el-icon>
                  <span>国家规则</span>
                </div>
              </el-button>
              
              <el-button-group>
                <el-button size="small" @click="openUpstreamDrawer(proxy)">
                  <el-icon><Edit24Regular /></el-icon>
                </el-button>
                <el-button size="small" type="danger" @click="deleteUpstream(proxy)">
                  <el-icon><Delete24Regular /></el-icon>
                </el-button>
              </el-button-group>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- ═══════════ 前置代理编辑 Drawer ═══════════ -->
    <el-drawer v-model="upstreamDrawerOpen" :title="editingUpstream ? '编辑前置代理' : '新增前置代理'" size="520px">
      <div class="space-y-6 pb-6">
        <div class="space-y-4">
          <div class="flex items-center gap-2 pb-2 border-b border-gray-100 dark:border-gray-800">
            <div class="w-1 h-4 bg-violet-500 rounded-full"></div>
            <h3 class="text-sm font-bold text-gray-900 dark:text-gray-100">代理信息</h3>
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div class="space-y-1">
              <label class="text-xs font-bold text-gray-500 uppercase tracking-wider">代理 ID</label>
              <el-input v-model="upstreamForm.id" :disabled="!!editingUpstream" placeholder="唯一标识，如 jp-proxy-01" />
            </div>
            <div class="space-y-1">
              <label class="text-xs font-bold text-gray-500 uppercase tracking-wider">名称</label>
              <el-input v-model="upstreamForm.name" placeholder="例如：日本代理" />
            </div>
          </div>

          <div class="space-y-1">
            <label class="text-xs font-bold text-gray-500 uppercase tracking-wider">Socks5 地址</label>
            <el-input v-model="upstreamForm.addr" placeholder="host:port，例如 1.2.3.4:1080 或 [2001:db8::1]:1080" />
            <div class="text-xs text-gray-400 mt-1">VoWiFi 通过此 Socks5 代理连接运营商，实现跨区域本地 VoWiFi。{{ upstreamProxyIPv6AddressHint }}。保存时会自动探测 Socks5 握手与 UDP Associate。</div>
          </div>

          <div class="ui-panel-muted p-3 flex items-center justify-between rounded-lg">
            <div>
              <div class="text-sm font-bold text-gray-800 dark:text-gray-100">启用代理</div>
              <div class="text-xs text-gray-500">禁用后绑定到该代理的国家规则会回退为直连</div>
            </div>
            <el-switch v-model="upstreamForm.enabled" />
          </div>
        </div>

        <div class="space-y-4">
          <div class="flex items-center gap-2 pb-2 border-b border-gray-100 dark:border-gray-800">
            <div class="w-1 h-4 bg-amber-500 rounded-full"></div>
            <h3 class="text-sm font-bold text-gray-900 dark:text-gray-100">鉴权设置（可选）</h3>
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div class="space-y-1">
              <label class="text-xs font-bold text-gray-500 uppercase tracking-wider">用户名</label>
              <el-input v-model="upstreamForm.username" placeholder="留空则免鉴权" />
            </div>
            <div class="space-y-1">
              <label class="text-xs font-bold text-gray-500 uppercase tracking-wider">密码</label>
              <el-input v-model="upstreamForm.password" type="password" show-password placeholder="留空则免鉴权" />
              <div class="text-xs text-gray-400 mt-1">编辑已有代理时留空会保持原密码不变。</div>
            </div>
          </div>
        </div>
      </div>

      <template #footer>
        <div class="flex items-center justify-end gap-2">
          <el-button @click="upstreamDrawerOpen = false">取消</el-button>
          <el-button type="primary" @click="saveUpstreamForm">
            {{ editingUpstream ? '更新' : '创建' }}
          </el-button>
        </div>
      </template>
    </el-drawer>

    <!-- ═══════════ 国家规则 Drawer ═══════════ -->
    <el-drawer v-model="countryRuleDrawerOpen" :title="`国家规则 — ${countryRuleTargetProxy?.name || countryRuleTargetProxy?.id || ''}`" size="560px">
      <div class="space-y-6 pb-6">
        <!-- 已配置国家规则 -->
        <div class="space-y-4">
          <div class="flex items-center gap-2 pb-2 border-b border-gray-100 dark:border-gray-800">
            <div class="w-1 h-4 bg-green-500 rounded-full"></div>
            <h3 class="text-sm font-bold text-gray-900 dark:text-gray-100">已路由到该代理的国家</h3>
          </div>

          <EmptyState
            v-if="currentProxyCountryRules.length === 0"
            title="暂无国家规则"
            subtitle="未配置的国家会默认直连"
          />

          <div v-else class="space-y-2">
            <div
              v-for="rule in currentProxyCountryRules"
              :key="rule.country_code"
              class="ui-panel-muted p-3 flex items-center justify-between rounded-lg"
            >
              <div class="flex items-center gap-2 min-w-0">
                <span class="w-2 h-2 rounded-full bg-green-500 shrink-0"></span>
                <div class="min-w-0">
                  <div class="text-sm font-medium text-gray-900 dark:text-white truncate">
                    {{ rule.country_code }} · {{ rule.country_name || rule.country_code }}
                  </div>
                  <div class="text-xs text-gray-400 font-mono truncate">MCC {{ rule.mccs.join('/') || '-' }}</div>
                </div>
              </div>
              <el-button size="small" type="danger" text @click="doDeleteCountryRule(rule.country_code)">
                删除规则
              </el-button>
            </div>
          </div>
        </div>

        <!-- 添加国家规则 -->
        <div class="space-y-4">
          <div class="flex items-center gap-2 pb-2 border-b border-gray-100 dark:border-gray-800">
            <div class="w-1 h-4 bg-blue-500 rounded-full"></div>
            <h3 class="text-sm font-bold text-gray-900 dark:text-gray-100">添加国家规则</h3>
          </div>

          <div class="flex items-center gap-2">
            <el-select v-model="selectedCountryCode" placeholder="选择国家" class="flex-1" filterable>
              <el-option
                v-for="country in availableCountries"
                :key="country.country_code"
                :label="formatCountryLabel(country)"
                :value="country.country_code"
              >
                <div class="flex items-center justify-between w-full">
                  <span>{{ country.country_code }} · {{ country.country_name || country.country_code }}</span>
                  <el-tag
                    v-if="upstreamStore.getRuleForCountry(country.country_code)?.upstream_proxy_id === countryRuleTargetProxy?.id"
                    size="small"
                    type="success"
                    class="ml-2"
                  >
                    已配置
                  </el-tag>
                  <span class="text-xs text-gray-400 font-mono ml-2">MCC {{ country.mccs.join('/') }}</span>
                </div>
              </el-option>
            </el-select>
            <el-button type="primary" @click="doUpsertCountryRule" :disabled="!selectedCountryCode">
              <el-icon class="mr-1.5"><Link24Regular /></el-icon>
              <span>保存规则</span>
            </el-button>
          </div>

          <el-alert type="info" :closable="false" show-icon class="!py-2">
            <template #default>
              <span class="text-xs">规则按 SIM 归属 MCC 解析国家。例如 US 会覆盖 MCC 310/311/312/313/314/315/316 等表内分组；没有配置规则的国家默认直连。需要重启 VoWiFi 生效。</span>
            </template>
          </el-alert>
        </div>
      </div>
    </el-drawer>
  </div>
</template>

<style scoped>
.proxy-tabs :deep(.el-tabs__header) {
  margin-bottom: 0;
}
.proxy-tabs :deep(.el-tabs__nav-wrap::after) {
  height: 1px;
}
</style>
