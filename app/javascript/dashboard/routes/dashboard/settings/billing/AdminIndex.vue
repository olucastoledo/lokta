<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'dashboard/composables/store.js';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import ButtonV4 from 'next/button/Button.vue';

const store = useStore();
const { t } = useI18n();
const currentUser = computed(() => store.getters.getCurrentUser);
const isSuperAdmin = computed(() => currentUser.value?.type === 'SuperAdmin');

// State
const accounts = ref([]);
const meta = ref({ current_page: 1, total_pages: 1, total_count: 0 });
const isLoading = ref(false);
const searchQuery = ref('');
const filterStatus = ref('');
const currentPage = ref(1);

// Selected Account details
const selectedAccount = ref(null);
const isLoadingDetails = ref(false);
const accountDetails = ref(null);

// Forms/Edit state
const isSyncing = ref({});
const uploadInvoiceId = ref(null);
const fileInput = ref(null);
const isUploading = ref(false);

// Edit subscription form
const editForm = ref({
  billing_enabled: true,
  stripe_customer_id: '',
  stripe_subscription_id: '',
  stripe_price_id: '',
  stripe_product_id: '',
  plan_name: '',
  amount: 0,
  currency: 'BRL',
  status: 'none',
  current_period_end: '',
  trial_end: '',
});
const isSaving = ref(false);

const fetchAccounts = async (page = 1) => {
  if (!isSuperAdmin.value) return;
  isLoading.value = true;
  currentPage.value = page;
  try {
    const response = await window.axios.get('/api/v1/billing/admin/accounts', {
      params: {
        q: searchQuery.value,
        status: filterStatus.value,
        page: page,
      },
    });
    accounts.value = response.data.accounts;
    meta.value = response.data.meta;
  } catch (err) {
    alert(
      'Erro ao carregar contas: ' + (err.response?.data?.error || err.message)
    );
  } finally {
    isLoading.value = false;
  }
};

const selectAccount = async account => {
  selectedAccount.value = account;
  isLoadingDetails.value = true;
  accountDetails.value = null;
  try {
    const response = await window.axios.get(
      `/api/v1/billing/admin/accounts/${account.id}`
    );
    accountDetails.value = response.data;

    // Populate form
    const sub = response.data.subscription || {};
    editForm.value = {
      billing_enabled: response.data.account.billing_enabled,
      stripe_customer_id: sub.stripe_customer_id || '',
      stripe_subscription_id: sub.stripe_subscription_id || '',
      stripe_price_id: sub.stripe_price_id || '',
      stripe_product_id: sub.stripe_product_id || '',
      plan_name: sub.plan_name || '',
      amount: sub.amount || 0,
      currency: sub.currency || 'BRL',
      status: sub.status || 'none',
      current_period_end: sub.current_period_end
        ? format(new Date(sub.current_period_end), 'yyyy-MM-dd')
        : '',
      trial_end: sub.trial_end
        ? format(new Date(sub.trial_end), 'yyyy-MM-dd')
        : '',
    };
  } catch (err) {
    alert(
      'Erro ao carregar detalhes da conta: ' +
        (err.response?.data?.error || err.message)
    );
  } finally {
    isLoadingDetails.value = false;
  }
};

const saveAccountSettings = async () => {
  if (!selectedAccount.value) return;
  isSaving.value = true;
  try {
    const payload = {
      billing_enabled: editForm.value.billing_enabled,
      subscription: {
        stripe_customer_id: editForm.value.stripe_customer_id,
        stripe_subscription_id: editForm.value.stripe_subscription_id,
        stripe_price_id: editForm.value.stripe_price_id,
        stripe_product_id: editForm.value.stripe_product_id,
        plan_name: editForm.value.plan_name,
        amount: editForm.value.amount,
        currency: editForm.value.currency,
        status: editForm.value.status,
        current_period_end: editForm.value.current_period_end || null,
        trial_end: editForm.value.trial_end || null,
      },
    };

    await window.axios.put(
      `/api/v1/billing/admin/accounts/${selectedAccount.value.id}`,
      payload
    );
    alert('Configurações salvas com sucesso!');
    await selectAccount(selectedAccount.value);
    await fetchAccounts(currentPage.value);
  } catch (err) {
    alert(
      'Erro ao salvar configurações: ' +
        (err.response?.data?.error || err.message)
    );
  } finally {
    isSaving.value = false;
  }
};

const syncStripe = async accountId => {
  isSyncing.value[accountId] = true;
  try {
    const response = await window.axios.post(
      `/api/v1/billing/admin/accounts/${accountId}/sync`
    );
    alert(response.data.message || 'Sincronizado com sucesso.');
    if (selectedAccount.value?.id === accountId) {
      await selectAccount(selectedAccount.value);
    }
    await fetchAccounts(currentPage.value);
  } catch (err) {
    alert(
      'Erro ao sincronizar com Stripe: ' +
        (err.response?.data?.error || err.message)
    );
  } finally {
    isSyncing.value[accountId] = false;
  }
};

const triggerFileUpload = invoiceId => {
  uploadInvoiceId.value = invoiceId;
  fileInput.value?.click();
};

const handleFileUpload = async event => {
  const file = event.target.files[0];
  if (!file || !uploadInvoiceId.value) return;

  const formData = new FormData();
  formData.append('file', file);

  isUploading.value = true;
  try {
    await window.axios.post(
      `/api/v1/billing/admin/invoices/${uploadInvoiceId.value}/upload_file`,
      formData,
      {
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      }
    );
    alert('Nota fiscal anexada com sucesso!');
    if (selectedAccount.value) {
      await selectAccount(selectedAccount.value);
    }
  } catch (err) {
    alert(
      'Erro ao enviar arquivo: ' + (err.response?.data?.error || err.message)
    );
  } finally {
    isUploading.value = false;
    uploadInvoiceId.value = null;
    if (fileInput.value) fileInput.value.value = '';
  }
};

// Helpers
const formatCurrency = (amount, currency = 'BRL') => {
  if (amount == null) return '-';
  const formattingCurrency = (currency || 'BRL').toUpperCase();
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: formattingCurrency,
  }).format(amount);
};

const formatDate = dateStr => {
  if (!dateStr) return '-';
  try {
    const date = new Date(dateStr);
    return format(date, 'dd/MM/yyyy HH:mm');
  } catch {
    return dateStr;
  }
};

const translateStatus = status => {
  const translations = {
    active: t('BILLING_SETTINGS.SELF_HOSTED.STATUS_ACTIVE'),
    trialing: t('BILLING_SETTINGS.SELF_HOSTED.STATUS_TRIALING'),
    past_due: t('BILLING_SETTINGS.SELF_HOSTED.STATUS_PAST_DUE'),
    unpaid: t('BILLING_SETTINGS.SELF_HOSTED.STATUS_UNPAID'),
    canceled: t('BILLING_SETTINGS.SELF_HOSTED.STATUS_CANCELED'),
    blocked: t('BILLING_SETTINGS.SELF_HOSTED.STATUS_BLOCKED'),
    none: t('BILLING_SETTINGS.SELF_HOSTED.STATUS_NONE'),
  };
  return translations[status] || status;
};

const translateInvoiceStatus = status => {
  const translations = {
    paid: t('BILLING_SETTINGS.SELF_HOSTED.INV_STATUS_PAID'),
    open: t('BILLING_SETTINGS.SELF_HOSTED.INV_STATUS_OPEN'),
    unpaid: t('BILLING_SETTINGS.SELF_HOSTED.INV_STATUS_UNPAID'),
    uncollectible: t('BILLING_SETTINGS.SELF_HOSTED.INV_STATUS_UNCOLLECTIBLE'),
    void: t('BILLING_SETTINGS.SELF_HOSTED.INV_STATUS_VOID'),
  };
  return translations[status] || status;
};

const statusColorClass = status => {
  if (['active', 'trialing'].includes(status))
    return 'text-emerald-600 font-bold';
  return 'text-red-600 font-bold';
};

const invoiceStatusClass = status => {
  if (status === 'paid') return 'bg-emerald-50 text-emerald-700';
  if (status === 'open') return 'bg-amber-50 text-amber-700';
  return 'bg-red-50 text-red-700';
};

onMounted(() => {
  fetchAccounts();
});
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :loading-message="$t('ATTRIBUTES_MGMT.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="$t('BILLING_SETTINGS.ADMIN_TITLE')"
        :description="$t('BILLING_SETTINGS.ADMIN.PANEL_DESC')"
        feature-name="billing-admin"
      />
    </template>

    <template #body>
      <div
        v-if="!isSuperAdmin"
        class="p-6 text-center bg-red-50 border border-red-200 rounded-lg"
      >
        <h3 class="text-lg font-bold text-red-800 mb-2">
          {{ $t('BILLING_SETTINGS.ADMIN.RESTRICTED_ACCESS_TITLE') }}
        </h3>
        <p class="text-sm text-red-600">
          {{ $t('BILLING_SETTINGS.ADMIN.RESTRICTED_ACCESS_DESC') }}
        </p>
      </div>

      <div v-else class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        <!-- Accounts List Section -->
        <div class="lg:col-span-7 flex flex-col gap-4">
          <!-- Filters & Search Bar -->
          <div
            class="flex gap-2 flex-wrap items-center bg-n-alpha p-3 rounded-lg border border-n-weak"
          >
            <input
              v-model="searchQuery"
              type="text"
              :placeholder="$t('BILLING_SETTINGS.ADMIN.SEARCH_PLACEHOLDER')"
              class="flex-1 min-w-[200px] border border-n-weak rounded px-3 py-1.5 text-sm bg-n-light focus:outline-none focus:border-blue-500"
              @keyup.enter="fetchAccounts(1)"
            />
            <select
              v-model="filterStatus"
              class="border border-n-weak rounded px-3 py-1.5 text-sm bg-n-light focus:outline-none focus:border-blue-500"
              @change="fetchAccounts(1)"
            >
              <option value="">
                {{ $t('BILLING_SETTINGS.ADMIN.ALL_STATUS') }}
              </option>
              <option value="active">
                {{ $t('BILLING_SETTINGS.SELF_HOSTED.STATUS_ACTIVE') }}
              </option>
              <option value="trialing">
                {{ $t('BILLING_SETTINGS.SELF_HOSTED.STATUS_TRIALING') }}
              </option>
              <option value="past_due">
                {{ $t('BILLING_SETTINGS.SELF_HOSTED.STATUS_PAST_DUE') }}
              </option>
              <option value="unpaid">
                {{ $t('BILLING_SETTINGS.SELF_HOSTED.STATUS_UNPAID') }}
              </option>
              <option value="canceled">
                {{ $t('BILLING_SETTINGS.SELF_HOSTED.STATUS_CANCELED') }}
              </option>
            </select>
            <ButtonV4 sm solid blue @click="fetchAccounts(1)">
              {{ $t('BILLING_SETTINGS.ADMIN.FILTER') }}
            </ButtonV4>
          </div>

          <!-- Accounts Table -->
          <div
            class="border border-n-weak rounded-lg overflow-hidden bg-n-light"
          >
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-n-weak text-sm">
                <thead class="bg-n-alpha">
                  <tr>
                    <th class="px-4 py-2 text-left font-semibold text-n-most">
                      {{ $t('BILLING_SETTINGS.ADMIN.ID') }}
                    </th>
                    <th class="px-4 py-2 text-left font-semibold text-n-most">
                      {{ $t('BILLING_SETTINGS.ADMIN.WORKSPACE') }}
                    </th>
                    <th class="px-4 py-2 text-left font-semibold text-n-most">
                      {{ $t('BILLING_SETTINGS.ADMIN.PLAN') }}
                    </th>
                    <th class="px-4 py-2 text-left font-semibold text-n-most">
                      {{ $t('BILLING_SETTINGS.SELF_HOSTED.STATUS') }}
                    </th>
                    <th class="px-4 py-2 text-left font-semibold text-n-most">
                      {{ $t('BILLING_SETTINGS.ADMIN.ACTIONS') }}
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-n-weak">
                  <tr
                    v-for="acc in accounts"
                    :key="acc.id"
                    class="hover:bg-n-alpha cursor-pointer transition-colors"
                    :class="{ 'bg-blue-50/50': selectedAccount?.id === acc.id }"
                    @click="selectAccount(acc)"
                  >
                    <td class="px-4 py-3 text-n-mild font-mono text-xs">
                      {{ acc.id }}
                    </td>
                    <td class="px-4 py-3 font-semibold text-n-most">
                      {{ acc.name }}
                    </td>
                    <td class="px-4 py-3 text-n-mild">
                      {{
                        acc.subscription?.plan_name ||
                        $t('BILLING_SETTINGS.SELF_HOSTED.CUSTOM_PLAN')
                      }}
                    </td>
                    <td class="px-4 py-3">
                      <span
                        v-if="acc.subscription"
                        class="inline-block px-2 py-0.5 rounded text-xs font-semibold"
                        :class="statusColorClass(acc.subscription.status)"
                      >
                        {{ translateStatus(acc.subscription.status) }}
                      </span>
                      <span v-else class="text-n-light text-xs">{{ '-' }}</span>
                    </td>
                    <td class="px-4 py-3" @click.stop>
                      <ButtonV4
                        v-if="acc.subscription?.stripe_subscription_id"
                        sm
                        flushed
                        blue
                        :is-loading="isSyncing[acc.id]"
                        icon="i-lucide-refresh-cw"
                        :title="$t('BILLING_SETTINGS.ADMIN.SYNC_TITLE')"
                        @click="syncStripe(acc.id)"
                      />
                      <span v-else class="text-xs text-n-light">{{
                        $t('BILLING_SETTINGS.ADMIN.NO_STRIPE_ID')
                      }}</span>
                    </td>
                  </tr>
                  <tr v-if="accounts.length === 0">
                    <td colspan="5" class="px-4 py-6 text-center text-n-mild">
                      {{ $t('BILLING_SETTINGS.ADMIN.NO_WORKSPACE_FOUND') }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <!-- Pagination -->
            <div
              v-if="meta.total_pages > 1"
              class="flex justify-between items-center px-4 py-3 border-t border-n-weak bg-n-alpha text-xs text-n-mild"
            >
              <div>
                {{
                  $t('BILLING_SETTINGS.ADMIN.TOTAL', {
                    count: meta.total_count,
                  })
                }}
              </div>
              <div class="flex gap-2">
                <ButtonV4
                  sm
                  flushed
                  slate
                  :disabled="meta.current_page === 1"
                  @click="fetchAccounts(meta.current_page - 1)"
                >
                  {{ $t('BILLING_SETTINGS.ADMIN.PREVIOUS') }}
                </ButtonV4>
                <span class="py-1 px-2">
                  {{
                    $t('BILLING_SETTINGS.ADMIN.PAGE_INFO', {
                      current: meta.current_page,
                      total: meta.total_pages,
                    })
                  }}
                </span>
                <ButtonV4
                  sm
                  flushed
                  slate
                  :disabled="meta.current_page === meta.total_pages"
                  @click="fetchAccounts(meta.current_page + 1)"
                >
                  {{ $t('BILLING_SETTINGS.ADMIN.NEXT') }}
                </ButtonV4>
              </div>
            </div>
          </div>
        </div>

        <!-- Detail/Edit Pane Section -->
        <div class="lg:col-span-5">
          <div
            v-if="selectedAccount"
            class="border border-n-weak rounded-lg p-5 bg-n-light flex flex-col gap-5"
          >
            <div
              class="flex justify-between items-start border-b border-n-weak pb-3"
            >
              <div>
                <span
                  class="text-xs text-blue-600 font-bold uppercase tracking-wider"
                >
                  {{
                    `${$t('BILLING_SETTINGS.ADMIN.WORKSPACE')} #${selectedAccount.id}`
                  }}
                </span>
                <h3 class="text-base font-bold text-n-most mt-0.5">
                  {{ selectedAccount.name }}
                </h3>
              </div>
              <ButtonV4 sm flushed slate @click="selectedAccount = null">
                {{ $t('BILLING_SETTINGS.ADMIN.CLOSE') }}
              </ButtonV4>
            </div>

            <!-- Loader for Details -->
            <div
              v-if="isLoadingDetails"
              class="py-12 text-center text-sm text-n-mild"
            >
              {{ $t('BILLING_SETTINGS.ADMIN.LOADING_DETAILS') }}
            </div>

            <div v-else-if="accountDetails" class="flex flex-col gap-6">
              <!-- Billing Status Toggle -->
              <div
                class="flex items-center justify-between bg-n-alpha p-3 rounded-lg border border-n-weak"
              >
                <div>
                  <h4 class="text-sm font-semibold text-n-most">
                    {{ $t('BILLING_SETTINGS.ADMIN.BILLING_ACTIVE') }}
                  </h4>
                  <p class="text-xs text-n-mild">
                    {{ $t('BILLING_SETTINGS.ADMIN.BILLING_ACTIVE_DESC') }}
                  </p>
                </div>
                <input
                  v-model="editForm.billing_enabled"
                  type="checkbox"
                  class="h-5 w-5 rounded border-n-weak text-blue-600 focus:ring-blue-500"
                />
              </div>

              <!-- Stripe Mapping Form -->
              <form
                class="flex flex-col gap-4"
                @submit.prevent="saveAccountSettings"
              >
                <h4
                  class="text-sm font-bold text-n-most border-b border-n-weak pb-1"
                >
                  {{ $t('BILLING_SETTINGS.ADMIN.LINK_STRIPE') }}
                </h4>

                <div class="grid grid-cols-2 gap-3">
                  <div class="flex flex-col gap-1 col-span-2">
                    <label class="text-xs font-semibold text-n-mild">{{
                      $t('BILLING_SETTINGS.ADMIN.CUSTOMER_ID')
                    }}</label>
                    <input
                      v-model="editForm.stripe_customer_id"
                      type="text"
                      :placeholder="
                        $t('BILLING_SETTINGS.ADMIN.CUSTOMER_ID_PLACEHOLDER')
                      "
                      class="border border-n-weak rounded px-3 py-1.5 text-sm bg-n-light focus:outline-none focus:border-blue-500"
                    />
                  </div>

                  <div class="flex flex-col gap-1 col-span-2">
                    <label class="text-xs font-semibold text-n-mild">{{
                      $t('BILLING_SETTINGS.ADMIN.SUBSCRIPTION_ID')
                    }}</label>
                    <input
                      v-model="editForm.stripe_subscription_id"
                      type="text"
                      :placeholder="
                        $t('BILLING_SETTINGS.ADMIN.SUBSCRIPTION_ID_PLACEHOLDER')
                      "
                      class="border border-n-weak rounded px-3 py-1.5 text-sm bg-n-light focus:outline-none focus:border-blue-500"
                    />
                  </div>

                  <div class="flex flex-col gap-1">
                    <label class="text-xs font-semibold text-n-mild">{{
                      $t('BILLING_SETTINGS.ADMIN.PLAN_NAME')
                    }}</label>
                    <input
                      v-model="editForm.plan_name"
                      type="text"
                      :placeholder="$t('BILLING_SETTINGS.ADMIN.PLAN_NAME')"
                      class="border border-n-weak rounded px-3 py-1.5 text-sm bg-n-light focus:outline-none focus:border-blue-500"
                    />
                  </div>

                  <div class="flex flex-col gap-1">
                    <label class="text-xs font-semibold text-n-mild">{{
                      $t('BILLING_SETTINGS.ADMIN.STATUS_LABEL')
                    }}</label>
                    <select
                      v-model="editForm.status"
                      class="border border-n-weak rounded px-3 py-1.5 text-sm bg-n-light focus:outline-none focus:border-blue-500"
                    >
                      <option value="none">
                        {{ $t('BILLING_SETTINGS.SELF_HOSTED.STATUS_NONE') }}
                      </option>
                      <option value="active">
                        {{ $t('BILLING_SETTINGS.SELF_HOSTED.STATUS_ACTIVE') }}
                      </option>
                      <option value="trialing">
                        {{ $t('BILLING_SETTINGS.SELF_HOSTED.STATUS_TRIALING') }}
                      </option>
                      <option value="past_due">
                        {{ $t('BILLING_SETTINGS.SELF_HOSTED.STATUS_PAST_DUE') }}
                      </option>
                      <option value="unpaid">
                        {{ $t('BILLING_SETTINGS.SELF_HOSTED.STATUS_UNPAID') }}
                      </option>
                      <option value="canceled">
                        {{ $t('BILLING_SETTINGS.SELF_HOSTED.STATUS_CANCELED') }}
                      </option>
                    </select>
                  </div>

                  <div class="flex flex-col gap-1">
                    <label class="text-xs font-semibold text-n-mild">{{
                      $t('BILLING_SETTINGS.ADMIN.MONTHLY_VALUE')
                    }}</label>
                    <input
                      v-model.number="editForm.amount"
                      type="number"
                      step="0.01"
                      class="border border-n-weak rounded px-3 py-1.5 text-sm bg-n-light focus:outline-none focus:border-blue-500"
                    />
                  </div>

                  <div class="flex flex-col gap-1">
                    <label class="text-xs font-semibold text-n-mild">{{
                      $t('BILLING_SETTINGS.ADMIN.CURRENCY')
                    }}</label>
                    <input
                      v-model="editForm.currency"
                      type="text"
                      class="border border-n-weak rounded px-3 py-1.5 text-sm bg-n-light focus:outline-none focus:border-blue-500"
                    />
                  </div>

                  <div class="flex flex-col gap-1">
                    <label class="text-xs font-semibold text-n-mild">{{
                      $t('BILLING_SETTINGS.ADMIN.NEXT_DUE')
                    }}</label>
                    <input
                      v-model="editForm.current_period_end"
                      type="date"
                      class="border border-n-weak rounded px-3 py-1.5 text-sm bg-n-light focus:outline-none focus:border-blue-500"
                    />
                  </div>

                  <div class="flex flex-col gap-1">
                    <label class="text-xs font-semibold text-n-mild">{{
                      $t('BILLING_SETTINGS.ADMIN.TRIAL_END')
                    }}</label>
                    <input
                      v-model="editForm.trial_end"
                      type="date"
                      class="border border-n-weak rounded px-3 py-1.5 text-sm bg-n-light focus:outline-none focus:border-blue-500"
                    />
                  </div>
                </div>

                <div class="flex justify-end gap-2 mt-2">
                  <ButtonV4
                    v-if="editForm.stripe_subscription_id"
                    sm
                    slate
                    flushed
                    :is-loading="isSyncing[selectedAccount.id]"
                    @click.prevent="syncStripe(selectedAccount.id)"
                  >
                    {{ $t('BILLING_SETTINGS.ADMIN.FORCE_SYNC') }}
                  </ButtonV4>
                  <ButtonV4 sm solid blue type="submit" :is-loading="isSaving">
                    {{ $t('BILLING_SETTINGS.ADMIN.SAVE_DATA') }}
                  </ButtonV4>
                </div>
              </form>

              <!-- Invoices & PDF Upload section -->
              <div class="flex flex-col gap-4">
                <h4
                  class="text-sm font-bold text-n-most border-b border-n-weak pb-1"
                >
                  {{ $t('BILLING_SETTINGS.ADMIN.INVOICES_TITLE') }}
                </h4>
                <div
                  v-if="
                    accountDetails.invoices &&
                    accountDetails.invoices.length > 0
                  "
                  class="flex flex-col gap-3 max-h-[300px] overflow-y-auto pr-1"
                >
                  <div
                    v-for="invoice in accountDetails.invoices"
                    :key="invoice.id"
                    class="border border-n-weak p-3 rounded bg-n-alpha flex flex-col gap-2"
                  >
                    <div class="flex justify-between items-start text-xs">
                      <div>
                        <div class="font-mono text-n-most">
                          {{ invoice.stripe_invoice_id || `MAN-${invoice.id}` }}
                        </div>
                        <div class="text-n-mild mt-0.5">
                          {{ formatDate(invoice.created_at) }}
                        </div>
                      </div>
                      <div class="flex flex-col items-end gap-1">
                        <span
                          class="px-1.5 py-0.5 rounded font-semibold scale-90"
                          :class="invoiceStatusClass(invoice.status)"
                        >
                          {{ translateInvoiceStatus(invoice.status) }}
                        </span>
                        <div class="font-bold text-n-most mt-0.5">
                          {{ formatCurrency(invoice.amount, invoice.currency) }}
                        </div>
                      </div>
                    </div>

                    <!-- Existing uploaded files list -->
                    <div
                      v-if="invoice.files && invoice.files.length > 0"
                      class="border-t border-n-weak pt-2 mt-1"
                    >
                      <div
                        class="text-[10px] uppercase font-bold text-n-mild tracking-wider mb-1"
                      >
                        {{ $t('BILLING_SETTINGS.ADMIN.ATTACHED_FILES') }}
                      </div>
                      <div class="flex flex-col gap-1">
                        <a
                          v-for="file in invoice.files"
                          :key="file.id"
                          :href="file.url"
                          download
                          class="text-emerald-600 text-xs hover:underline flex items-center gap-1"
                        >
                          📄 {{ file.filename }}
                        </a>
                      </div>
                    </div>

                    <!-- Action to upload manual invoice PDF -->
                    <div class="flex justify-end mt-1">
                      <ButtonV4
                        sm
                        flushed
                        emerald
                        icon="i-lucide-upload"
                        @click="triggerFileUpload(invoice.id)"
                      >
                        {{ $t('BILLING_SETTINGS.ADMIN.ATTACH_PDF') }}
                      </ButtonV4>
                    </div>
                  </div>
                </div>
                <div
                  v-else
                  class="text-center text-xs text-n-mild py-6 border border-dashed border-n-weak rounded"
                >
                  {{ $t('BILLING_SETTINGS.ADMIN.NO_INVOICES_FOUND') }}
                </div>
              </div>

              <!-- Audit Events Logs -->
              <div class="flex flex-col gap-4">
                <h4
                  class="text-sm font-bold text-n-most border-b border-n-weak pb-1"
                >
                  {{ $t('BILLING_SETTINGS.ADMIN.AUDIT_TITLE') }}
                </h4>
                <div
                  v-if="
                    accountDetails.events && accountDetails.events.length > 0
                  "
                  class="flex flex-col gap-2 max-h-[200px] overflow-y-auto text-xs bg-n-alpha p-3 rounded-lg border border-n-weak font-mono"
                >
                  <div
                    v-for="ev in accountDetails.events"
                    :key="ev.id"
                    class="border-b border-n-weak last:border-b-0 pb-1 mb-1"
                  >
                    <span class="text-blue-600">{{
                      `[${formatDate(ev.created_at)}]`
                    }}</span>
                    <span class="text-n-most font-bold">
                      {{ ev.event_type }}
                    </span>
                    {{ ': ' }}
                    <span class="text-n-mild">{{ ev.description }}</span>
                  </div>
                </div>
                <div
                  v-else
                  class="text-center text-xs text-n-mild py-4 border border-dashed border-n-weak rounded"
                >
                  {{ $t('BILLING_SETTINGS.ADMIN.NO_EVENTS') }}
                </div>
              </div>
            </div>
          </div>
          <div
            v-else
            class="py-24 text-center border border-dashed border-n-weak rounded-lg bg-n-alpha text-sm text-n-mild"
          >
            {{ $t('BILLING_SETTINGS.ADMIN.SELECT_WORKSPACE_PROMPT') }}
          </div>
        </div>
      </div>

      <!-- Hidden File Input for PDF Upload -->
      <input
        ref="fileInput"
        type="file"
        accept=".pdf"
        class="hidden"
        @change="handleFileUpload"
      />
    </template>
  </SettingsLayout>
</template>
