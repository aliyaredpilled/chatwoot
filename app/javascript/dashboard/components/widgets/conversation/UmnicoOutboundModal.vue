<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

import umnicoAPI from 'dashboard/api/umnico';

const { t } = useI18n();

const dialogRef = ref(null);
const integrations = ref([]);
const isLoadingIntegrations = ref(false);
const isSending = ref(false);
const selectedSaId = ref('');
const destination = ref('');
const message = ref('');

const inboxes = useMapGetter('inboxes/getInboxes');

const umnicoInbox = computed(() =>
  inboxes.value.find(inbox => inbox.channel_type === INBOX_TYPES.UMNICO)
);

const integrationOptions = computed(() =>
  integrations.value.map(integration => ({
    value: integration.id,
    label: `${integration.type} — ${integration.login}`,
  }))
);

const isFormValid = computed(
  () => selectedSaId.value && destination.value.trim() && message.value.trim()
);

const loadIntegrations = async () => {
  if (!umnicoInbox.value) return;
  isLoadingIntegrations.value = true;
  try {
    const { data } = await umnicoAPI.getIntegrations(umnicoInbox.value.id);
    integrations.value = data;
    if (data.length === 1) {
      selectedSaId.value = data[0].id;
    }
  } catch {
    // silently fail — user will see empty list
  } finally {
    isLoadingIntegrations.value = false;
  }
};

const resetForm = () => {
  selectedSaId.value = '';
  destination.value = '';
  message.value = '';
};

const open = () => {
  resetForm();
  dialogRef.value?.open();
};

const handleSend = async () => {
  if (!isFormValid.value || !umnicoInbox.value) return;
  isSending.value = true;
  try {
    await umnicoAPI.sendOutbound({
      inboxId: umnicoInbox.value.id,
      saId: selectedSaId.value,
      destination: destination.value.trim(),
      message: message.value.trim(),
    });
    useAlert(t('UMNICO_OUTBOUND.SUCCESS'));
    dialogRef.value?.close();
  } catch {
    useAlert(t('UMNICO_OUTBOUND.ERROR'));
  } finally {
    isSending.value = false;
  }
};

onMounted(loadIntegrations);

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('UMNICO_OUTBOUND.TITLE')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    width="md"
  >
    <div
      v-if="isLoadingIntegrations"
      class="flex items-center gap-2 text-sm text-n-slate-11"
    >
      <Spinner class="!w-4 !h-4" />
      <span>{{ t('UMNICO_OUTBOUND.LOADING_INTEGRATIONS') }}</span>
    </div>

    <p v-else-if="integrations.length === 0" class="text-sm text-n-slate-11">
      {{ t('UMNICO_OUTBOUND.NO_INTEGRATIONS') }}
    </p>

    <form v-else class="flex flex-col gap-4" @submit.prevent="handleSend">
      <div class="flex flex-col gap-1">
        <label class="mb-0.5 text-sm font-medium text-n-slate-12">
          {{ t('UMNICO_OUTBOUND.INTEGRATION_LABEL') }}
        </label>
        <ComboBox
          v-model="selectedSaId"
          :options="integrationOptions"
          :placeholder="t('UMNICO_OUTBOUND.INTEGRATION_PLACEHOLDER')"
          class="[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
        />
      </div>

      <Input
        v-model="destination"
        :label="t('UMNICO_OUTBOUND.DESTINATION_LABEL')"
        :placeholder="t('UMNICO_OUTBOUND.DESTINATION_PLACEHOLDER')"
      />

      <TextArea
        v-model="message"
        :label="t('UMNICO_OUTBOUND.MESSAGE_LABEL')"
        :placeholder="t('UMNICO_OUTBOUND.MESSAGE_PLACEHOLDER')"
        show-character-count
      />

      <div class="flex items-center justify-between w-full gap-3">
        <Button
          variant="faded"
          color="slate"
          type="button"
          :label="t('UMNICO_OUTBOUND.CANCEL_BUTTON')"
          class="w-full"
          @click="dialogRef?.close()"
        />
        <Button
          type="submit"
          :label="t('UMNICO_OUTBOUND.SEND_BUTTON')"
          color="blue"
          class="w-full"
          :is-loading="isSending"
          :disabled="isSending || !isFormValid"
        />
      </div>
    </form>
  </Dialog>
</template>
