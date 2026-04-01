<script setup>
import { ref, computed, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import NextButton from 'dashboard/components-next/button/Button.vue';

const SUGGESTION_MARKER = '[AGENT_SUGGESTION]';
const TRACE_MARKER = '[AGENT_TRACE]';
const WORKING_MARKER = '[AGENT_WORKING]';
const HANDOFF_MARKER = '[AGENT_HANDOFF]';
const NO_REPLY_MARKER = '[AGENT_NO_REPLY]';
const CORRECTION_FEEDBACK_MARKER = '[AGENT_CORRECTION_FEEDBACK]';
const TECHNICAL_MARKERS = [
  SUGGESTION_MARKER,
  TRACE_MARKER,
  WORKING_MARKER,
  HANDOFF_MARKER,
  NO_REPLY_MARKER,
  CORRECTION_FEEDBACK_MARKER,
];

const emit = defineEmits(['accept', 'edit', 'dismiss']);

const currentChat = useMapGetter('getSelectedChat');

const banner = ref(null);
const bannerContext = ref(null);

const hasBanner = computed(() => !!banner.value);

const messages = computed(() => currentChat.value?.messages || []);

const parseTechnicalMessage = (content, marker) => {
  if (!content || !content.startsWith(marker)) return null;

  const payload = content.slice(marker.length).trim();
  if (!payload) return { raw: '', data: null };

  try {
    return {
      raw: payload,
      data: JSON.parse(payload),
    };
  } catch {
    return {
      raw: payload,
      data: null,
    };
  }
};

const isTechnicalMessage = message => {
  const content = message?.content || '';
  return (
    !!message?.private &&
    TECHNICAL_MARKERS.some(marker => content.startsWith(marker))
  );
};

const findTraceMessageId = runId => {
  if (!runId) return null;

  for (let i = messages.value.length - 1; i >= 0; i -= 1) {
    const msg = messages.value[i];
    const parsed = parseTechnicalMessage(msg?.content, TRACE_MARKER);
    if (parsed?.data?.runId === runId) {
      return msg.id ?? null;
    }
  }

  return null;
};

const buildBannerState = message => {
  if (!message?.private) return null;

  const suggestion = parseTechnicalMessage(message?.content, SUGGESTION_MARKER);
  const suggestionText = suggestion?.data?.text || suggestion?.raw || '';
  if (suggestionText.trim()) {
    return {
      kind: 'suggestion',
      messageId: message.id ?? null,
      title: 'Предложение агента',
      text: suggestionText.trim(),
      titleClass: 'text-n-iris-11',
      iconClass: 'i-lucide-sparkles',
      panelClass: 'mx-2 mb-2 rounded-lg border border-n-iris-6 bg-n-iris-3 p-3',
      closeClass: 'text-n-iris-9 hover:text-n-iris-11',
      runId: suggestion?.data?.runId ?? null,
      suggestionMessageId: message.id ?? null,
      traceMessageId: findTraceMessageId(suggestion?.data?.runId),
    };
  }

  const handoff = parseTechnicalMessage(message?.content, HANDOFF_MARKER);
  if (handoff) {
    const handoffText =
      handoff?.data?.text || handoff?.raw || 'Диалог передан оператору.';
    return {
      kind: 'handoff',
      messageId: message.id ?? null,
      title: 'Агент просит вашу помощь',
      text: handoffText.trim(),
      subtitle: 'Диалог передан оператору',
      titleClass: 'text-n-amber-12',
      iconClass: 'i-lucide-hand',
      panelClass:
        'mx-2 mb-2 rounded-lg border border-n-amber-7 bg-n-amber-3 p-3',
      closeClass: 'text-n-amber-10 hover:text-n-amber-12',
    };
  }

  const noReply = parseTechnicalMessage(message?.content, NO_REPLY_MARKER);
  if (noReply) {
    return {
      kind: 'no_reply',
      messageId: message.id ?? null,
      title: 'Агент промолчал',
      text: 'Похоже, диалог сейчас ведёт оператор.',
      titleClass: 'text-n-slate-12',
      iconClass: 'i-lucide-bell-off',
      panelClass:
        'mx-2 mb-2 rounded-lg border border-n-slate-5 bg-n-slate-2 p-3',
      closeClass: 'text-n-slate-10 hover:text-n-slate-12',
    };
  }

  return null;
};

const syncBannerFromMessages = () => {
  if (!messages.value.length) {
    banner.value = null;
    bannerContext.value = null;
    return;
  }

  const recent = messages.value.slice(-10);
  for (let i = recent.length - 1; i >= 0; i -= 1) {
    const msg = recent[i];
    const nextBanner = buildBannerState(msg);

    if (nextBanner) {
      if (msg.id !== bannerContext.value?.messageId) {
        banner.value = nextBanner;
        bannerContext.value = nextBanner;
      }
      return;
    }

    if (!msg?.private || !isTechnicalMessage(msg)) {
      banner.value = null;
      bannerContext.value = null;
      return;
    }
  }

  banner.value = null;
  bannerContext.value = null;
};

watch(
  [() => currentChat.value?.id, () => messages.value.length],
  syncBannerFromMessages,
  { immediate: true }
);

const onAccept = () => {
  emit('accept', bannerContext.value);
  banner.value = null;
  bannerContext.value = null;
};

const onEdit = () => {
  emit('edit', bannerContext.value);
  banner.value = null;
  bannerContext.value = null;
};

const onDismiss = () => {
  emit('dismiss', bannerContext.value);
  banner.value = null;
  bannerContext.value = null;
};
</script>

<template>
  <Transition
    enter-active-class="transition-all duration-300 ease-out"
    enter-from-class="opacity-0 -translate-y-2"
    enter-to-class="opacity-100 translate-y-0"
    leave-active-class="transition-all duration-200 ease-in"
    leave-from-class="opacity-100 translate-y-0"
    leave-to-class="opacity-0 -translate-y-2"
  >
    <div v-if="hasBanner" :class="banner.panelClass">
      <div class="flex items-start justify-between gap-2 mb-2">
        <div class="flex items-center gap-1.5 text-xs font-medium" :class="banner.titleClass">
          <span :class="[banner.iconClass, 'size-3.5']" />
          {{ banner.title }}
        </div>
        <button :class="['transition-colors', banner.closeClass]" @click="onDismiss">
          <span class="i-lucide-x size-3.5" />
        </button>
      </div>
      <div
        v-if="banner.subtitle"
        class="text-xs text-n-slate-11 mb-2"
      >
        {{ banner.subtitle }}
      </div>
      <div class="text-sm text-n-slate-12 mb-3 whitespace-pre-wrap leading-relaxed">
        {{ banner.text }}
      </div>
      <div v-if="banner.kind === 'suggestion'" class="flex gap-2">
        <NextButton
          xs
          color="blue"
          variant="solid"
          icon="i-lucide-send"
          label="Отправить"
          @click="onAccept"
        />
        <NextButton
          xs
          color="blue"
          variant="faded"
          icon="i-lucide-pencil"
          label="Редактировать"
          @click="onEdit"
        />
      </div>
    </div>
  </Transition>
</template>
