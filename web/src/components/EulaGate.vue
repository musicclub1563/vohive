<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { systemService } from '../services/system'
import { errorMessage } from '../services/http'

const STORAGE_KEY = 'vohive_eula_accepted'
const REQUIRED_PHRASE = '我同意并确认'

const visible = ref(false)
const confirmText = ref('')
const uninstalling = ref(false)
const uninstallDone = ref(false)
const errorMsg = ref('')

const canAccept = computed(() => confirmText.value.trim() === REQUIRED_PHRASE)

// 免责声明条款（按截图正式文案）
const clauses = [
  '本软件（VoHive）属于个人开发者业余时间开发的工具软件，仅供技术研究、学习交流和个人内部测试使用。<strong class="font-semibold text-red-500">严禁用于任何商业用途</strong>，严禁作为生产环境的基础设施。',
  '使用者承诺将严格遵守所在国家或地区的相关法律法规。<strong class="font-semibold text-red-500">严禁将本软件用于电信诈骗、垃圾短信发送、非法网络代理、渗透测试或任何非法或违规场景</strong>。',
  '本软件涉及底层 Modem 通信操作，可能包含未知的缺陷。对于因使用本软件引发的硬件损坏、通信资源异常、隐私泄露等直接或间接损失，<strong class="font-semibold text-red-500">均由使用者自行承担所有责任</strong>。',
  '一旦点击继续即表示无条件接受本协议。如果拒绝，本软件将立即触发自毁与环境清理机制以确保设备安全。'
]

function readAccepted(): boolean {
  try {
    return localStorage.getItem(STORAGE_KEY) === 'true'
  } catch {
    return false
  }
}

// 仅在首次安装且尚未确认时展示协议，与是否登录无关。
function syncVisibility() {
  visible.value = !readAccepted()
}

onMounted(syncVisibility)

function accept() {
  if (!canAccept.value) return
  try {
    localStorage.setItem(STORAGE_KEY, 'true')
  } catch {
    // localStorage 不可用时忽略，仅当前会话生效
  }
  visible.value = false
}

// 禁止复制粘贴示例文案，强制用户手动输入以确认已阅读协议。
function onPasteBlocked() {
  errorMsg.value = '为保证您已阅读本协议，不支持复制粘贴，请手动输入「我同意并确认」'
}

async function rejectAndUninstall() {
  if (uninstalling.value) return
  uninstalling.value = true
  errorMsg.value = ''
  const res = await systemService.uninstall()
  if (res.ok) {
    // 后端已接受卸载请求，将异步执行自毁并退出进程。
    // 前端切到"卸载完成"页面持续提示，等待用户手动关闭浏览器。
    uninstallDone.value = true
  } else {
    uninstalling.value = false
    errorMsg.value = errorMessage(res.error, '卸载请求失败')
  }
}
</script>

<template>
  <!-- 卸载完成：全屏黑屏 + 红色三角警告 -->
  <div
    v-if="uninstallDone"
    class="fixed inset-0 z-[9999] flex items-center justify-center bg-black"
  >
    <div class="text-center">
      <svg
        xmlns="http://www.w3.org/2000/svg"
        width="48"
        height="48"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
        class="mx-auto text-red-500"
      >
        <path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z" />
        <path d="M12 9v4" />
        <path d="M12 17h.01" />
      </svg>
      <p class="mt-4 text-base font-medium tracking-wide text-red-500">软件已被卸载 / 服务已终止</p>
    </div>
  </div>

  <!-- 协议弹窗：深色遮罩背景 -->
  <div
    v-else-if="visible"
    class="fixed inset-0 z-[9999] flex items-center justify-center overflow-y-auto bg-slate-900/80 p-4"
  >
    <div
      class="flex max-h-[90vh] w-full max-w-2xl flex-col overflow-hidden rounded-2xl border border-slate-200/60 bg-white shadow-2xl dark:border-slate-700/60 dark:bg-[#1a1a20]"
    >
      <!-- 卡片顶部装饰渐变条（teal → 绿 → 黄） -->
      <div class="h-2.5 w-full bg-gradient-to-r from-cyan-400 via-green-400 to-yellow-300"></div>
      <!-- 顶部品牌图标：VoHive 应用图标样式（teal 圆形 + 白色 V），按你提供的图标配色 -->
      <div class="flex justify-center px-8 pt-8 pb-3">
        <div class="flex h-16 w-16 items-center justify-center rounded-full bg-teal-500 shadow-lg shadow-teal-500/30">
          <span class="text-3xl font-bold text-white">V</span>
        </div>
      </div>

      <!-- 标题 -->
      <div class="px-8 pt-1 pb-5 text-center">
        <h2 class="text-xl font-bold text-slate-900 dark:text-slate-100">VoHive 最终用户许可与免责声明</h2>
      </div>

      <!-- 条款：每条带蓝色数字徽章 + 关键词加粗红色 -->
      <div class="space-y-3 overflow-y-auto px-8 py-2 text-sm leading-relaxed text-slate-700 dark:text-slate-300">
        <div v-for="(c, i) in clauses" :key="i" class="flex gap-3">
          <div
            class="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-blue-100 text-xs font-semibold text-blue-600 dark:bg-blue-900/40 dark:text-blue-300"
          >
            {{ i + 1 }}
          </div>
          <p class="flex-1" v-html="c"></p>
        </div>
      </div>

      <!-- 输入框 + 按钮 -->
      <div class="space-y-3 px-8 pt-5 pb-7">
        <p class="text-center text-xs text-slate-500 dark:text-slate-400">
          请输入「<strong class="text-slate-700 dark:text-slate-200">我同意并确认</strong>」以解锁按钮
        </p>
        <input
          v-model="confirmText"
          type="text"
          placeholder="请手动输入：我同意并确认（不支持复制粘贴）"
          class="w-full rounded-lg border border-slate-200 bg-slate-100 px-3 py-2.5 text-center text-sm text-slate-900 outline-none placeholder:text-slate-400 focus:border-teal-500 focus:bg-white focus:ring-2 focus:ring-teal-500/20 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100"
          @paste.prevent="onPasteBlocked"
          @drop.prevent="onPasteBlocked"
        />
        <p v-if="errorMsg" class="text-center text-xs text-red-500">{{ errorMsg }}</p>
        <div class="flex items-center justify-center gap-3 pt-1">
          <button
            :disabled="uninstalling"
            class="rounded-lg border border-slate-200 bg-white px-5 py-2 text-sm text-slate-700 hover:bg-slate-50 disabled:opacity-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
            @click="rejectAndUninstall"
          >
            {{ uninstalling ? '正在卸载…' : '拒绝并卸载' }}
          </button>
          <button
            :disabled="!canAccept"
            :class="
              canAccept
                ? 'bg-teal-600 text-white hover:bg-teal-500 shadow'
                : 'bg-slate-200 text-slate-400 dark:bg-slate-800 dark:text-slate-500'
            "
            class="rounded-lg px-5 py-2 text-sm font-medium disabled:cursor-not-allowed"
            @click="accept"
          >
            同意并继续
          </button>
        </div>
      </div>
    </div>
  </div>
</template>