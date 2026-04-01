<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  isSaving: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['save', 'skip', 'update:show']);

const { t } = useI18n();

const comment = ref('');

const localShow = computed({
  get() {
    return props.show;
  },
  set(value) {
    emit('update:show', value);
  },
});

const isSaveDisabled = computed(() => props.isSaving || !comment.value.trim());

watch(
  () => props.show,
  value => {
    if (value) {
      comment.value = '';
    }
  }
);

const handleSkip = () => {
  if (props.isSaving) return;
  localShow.value = false;
  emit('skip');
};

const handleSave = () => {
  const trimmedComment = comment.value.trim();
  if (!trimmedComment) return;

  emit('save', trimmedComment);
};

const onClose = () => {
  handleSkip();
};
</script>

<template>
  <woot-modal v-model:show="localShow" :on-close="onClose">
    <woot-modal-header
      :header-title="t('CONVERSATION.REPLYBOX.CORRECTION_FEEDBACK.TITLE')"
      :header-content="t('CONVERSATION.REPLYBOX.CORRECTION_FEEDBACK.DESCRIPTION')"
    />

    <div class="px-6 py-5">
      <TextArea
        v-model="comment"
        :label="t('CONVERSATION.REPLYBOX.CORRECTION_FEEDBACK.LABEL')"
        :placeholder="
          t('CONVERSATION.REPLYBOX.CORRECTION_FEEDBACK.PLACEHOLDER')
        "
        class="mb-3"
        autofocus
      />

      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('CONVERSATION.REPLYBOX.CORRECTION_FEEDBACK.HINT') }}
      </p>

      <div class="mt-5 flex items-center justify-end gap-2">
        <Button
          :label="t('CONVERSATION.REPLYBOX.CORRECTION_FEEDBACK.SKIP')"
          color="slate"
          variant="faded"
          :disabled="isSaving"
          @click="handleSkip"
        />
        <Button
          :label="t('CONVERSATION.REPLYBOX.CORRECTION_FEEDBACK.SAVE')"
          color="blue"
          :disabled="isSaveDisabled"
          :is-loading="isSaving"
          @click="handleSave"
        />
      </div>
    </div>
  </woot-modal>
</template>
