<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store.js';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { format } from 'date-fns';
import sessionStorage from 'shared/helpers/sessionStorage';

import BillingMeter from './components/BillingMeter.vue';
import BillingCard from './components/BillingCard.vue';
import BillingHeader from './components/BillingHeader.vue';
import DetailItem from './components/DetailItem.vue';
import PurchaseCreditsModal from './components/PurchaseCreditsModal.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import ButtonV4 from 'next/button/Button.vue';

const { t } = useI18n();
const { currentAccount, isOnChatwootCloud } = useAccount();
const {
  captainEnabled,
  captainLimits,
  documentLimits,
  responseLimits,
  fetchLimits,
  isFetchingLimits,
} = useCaptain();

const uiFlags = useMapGetter('accounts/getUIFlags');
const store = useStore();

const BILLING_REFRESH_ATTEMPTED = 'billing_refresh_attempted';

// State for handling refresh attempts and loading
const isWaitingForBilling = ref(false);
const purchaseCreditsModalRef = ref(null);

// Self-Hosted Billing State
const selfHostedBilling = ref(null);
const isLoadingSelfHosted = ref(false);
const errorSelfHosted = ref('');

const customAttributes = computed(() => {
  return currentAccount.value.custom_attributes || {};
});

const planName = computed(() => {
  return customAttributes.value.plan_name;
});

const canPurchaseCredits = computed(() => {
  const plan = planName.value?.toLowerCase();
  return plan && plan !== 'hacker';
});

const subscribedQuantity = computed(() => {
  return customAttributes.value.subscribed_quantity;
});

const subscriptionRenewsOn = computed(() => {
  if (!customAttributes.value.subscription_ends_on) return '';
  const endDate = new Date(customAttributes.value.subscription_ends_on);
  return format(endDate, 'dd MMM, yyyy');
});

const hasABillingPlan = computed(() => {
  return !!planName.value;
});

const fetchAccountDetails = async () => {
  if (!hasABillingPlan.value) {
    await store.dispatch('accounts/subscription');
  }
  fetchLimits();
};

const fetchSelfHostedBilling = async () => {
  isLoadingSelfHosted.value = true;
  try {
    const accountId = currentAccount.value.id;
    const response = await window.axios.get(
      `/api/v1/accounts/${accountId}/billing`
    );
    selfHostedBilling.value = response.data;
  } catch (err) {
    errorSelfHosted.value = err.response?.data?.message || err.message;
  } finally {
    isLoadingSelfHosted.value = false;
  }
};

const handleBillingPageLogic = async () => {
  if (!isOnChatwootCloud.value) {
    await fetchSelfHostedBilling();
    return;
  }

  const billingRefreshAttempted = sessionStorage.get(BILLING_REFRESH_ATTEMPTED);
  await fetchAccountDetails();

  if (!hasABillingPlan.value) {
    if (!billingRefreshAttempted) {
      isWaitingForBilling.value = true;
      sessionStorage.set(BILLING_REFRESH_ATTEMPTED, true);
      setTimeout(() => {
        window.location.reload();
      }, 5000);
    } else {
      sessionStorage.remove(BILLING_REFRESH_ATTEMPTED);
    }
  } else {
    sessionStorage.remove(BILLING_REFRESH_ATTEMPTED);
  }
};

const onClickBillingPortal = () => {
  store.dispatch('accounts/checkout');
};

const checkoutPlan = async priceId => {
  try {
    const accountId = currentAccount.value.id;
    const response = await window.axios.post(
      `/api/v1/accounts/${accountId}/billing/checkout`,
      {
        price_id: priceId,
      }
    );
    if (response.data?.url) {
      window.location.href = response.data.url;
    }
  } catch (err) {
    alert(
      'Erro ao iniciar checkout: ' + (err.response?.data?.error || err.message)
    );
  }
};

const openStripePortal = async () => {
  try {
    const accountId = currentAccount.value.id;
    const response = await window.axios.post(
      `/api/v1/accounts/${accountId}/billing/portal`
    );
    if (response.data?.url) {
      window.location.href = response.data.url;
    }
  } catch (err) {
    alert(
      'Erro ao abrir portal do Stripe: ' +
        (err.response?.data?.error || err.message)
    );
  }
};

const onToggleChatWindow = () => {
  if (window.$chatwoot) {
    window.$chatwoot.toggle();
  }
};

const openPurchaseCreditsModal = () => {
  purchaseCreditsModalRef.value?.open();
};

const handleTopupSuccess = () => {
  fetchLimits();
};

// Formatting helpers
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
    return format(date, 'dd/MM/yyyy');
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

onMounted(handleBillingPageLogic);
</script>

<template>
  <SettingsLayout
    :is-loading="
      uiFlags.isFetchingItem || isWaitingForBilling || isLoadingSelfHosted
    "
    :loading-message="$t('ATTRIBUTES_MGMT.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="
          isOnChatwootCloud
            ? $t('BILLING_SETTINGS.TITLE')
            : 'Assinatura e Faturamento'
        "
        :description="
          isOnChatwootCloud
            ? $t('BILLING_SETTINGS.DESCRIPTION')
            : 'Gerencie seu plano de assinatura, faturas e formas de pagamento.'
        "
        feature-name="billing"
      />
    </template>
    <template #body>
      <!-- Original Cloud UI -->
      <section v-if="isOnChatwootCloud" class="grid gap-4">
        <BillingCard
          :title="$t('BILLING_SETTINGS.MANAGE_SUBSCRIPTION.TITLE')"
          :description="$t('BILLING_SETTINGS.MANAGE_SUBSCRIPTION.DESCRIPTION')"
        >
          <template #action>
            <ButtonV4 sm solid blue @click="onClickBillingPortal">
              {{ $t('BILLING_SETTINGS.MANAGE_SUBSCRIPTION.BUTTON_TXT') }}
            </ButtonV4>
          </template>
          <div
            v-if="planName || subscribedQuantity || subscriptionRenewsOn"
            class="grid lg:grid-cols-4 sm:grid-cols-3 grid-cols-1 gap-2 divide-x divide-n-weak"
          >
            <DetailItem
              :label="$t('BILLING_SETTINGS.CURRENT_PLAN.TITLE')"
              :value="planName"
            />
            <DetailItem
              v-if="subscribedQuantity"
              :label="$t('BILLING_SETTINGS.CURRENT_PLAN.SEAT_COUNT')"
              :value="subscribedQuantity"
            />
            <DetailItem
              v-if="subscriptionRenewsOn"
              :label="$t('BILLING_SETTINGS.CURRENT_PLAN.RENEWS_ON')"
              :value="subscriptionRenewsOn"
            />
          </div>
        </BillingCard>
        <BillingCard
          v-if="captainEnabled"
          :title="$t('BILLING_SETTINGS.CAPTAIN.TITLE')"
          :description="$t('BILLING_SETTINGS.CAPTAIN.DESCRIPTION')"
        >
          <template #action>
            <div class="flex gap-2">
              <ButtonV4
                sm
                flushed
                slate
                icon="i-lucide-refresh-cw"
                :is-loading="isFetchingLimits"
                @click="fetchLimits"
              >
                {{ $t('BILLING_SETTINGS.CAPTAIN.REFRESH_CREDITS') }}
              </ButtonV4>
              <ButtonV4
                v-if="canPurchaseCredits"
                sm
                solid
                blue
                @click="openPurchaseCreditsModal"
              >
                {{ $t('BILLING_SETTINGS.TOPUP.BUY_CREDITS') }}
              </ButtonV4>
            </div>
          </template>
          <div v-if="captainLimits && responseLimits" class="px-5">
            <BillingMeter
              :title="$t('BILLING_SETTINGS.CAPTAIN.RESPONSES')"
              v-bind="responseLimits"
            />
          </div>
          <div v-if="captainLimits && documentLimits" class="px-5">
            <BillingMeter
              :title="$t('BILLING_SETTINGS.CAPTAIN.DOCUMENTS')"
              v-bind="documentLimits"
            />
          </div>
        </BillingCard>
        <BillingCard
          v-else
          :title="$t('BILLING_SETTINGS.CAPTAIN.TITLE')"
          :description="$t('BILLING_SETTINGS.CAPTAIN.UPGRADE')"
        >
          <template #action>
            <ButtonV4 sm solid slate @click="onClickBillingPortal">
              {{ $t('CAPTAIN.PAYWALL.UPGRADE_NOW') }}
            </ButtonV4>
          </template>
        </BillingCard>

        <BillingHeader
          class="px-1 mt-5"
          :title="$t('BILLING_SETTINGS.CHAT_WITH_US.TITLE')"
          :description="$t('BILLING_SETTINGS.CHAT_WITH_US.DESCRIPTION')"
        >
          <ButtonV4
            sm
            solid
            slate
            icon="i-lucide-life-buoy"
            @click="onToggleChatWindow"
          >
            {{ $t('BILLING_SETTINGS.CHAT_WITH_US.BUTTON_TXT') }}
          </ButtonV4>
        </BillingHeader>
      </section>

      <!-- Custom Self-Hosted UI -->
      <section v-else class="grid gap-4">
        <!-- Billing Block Warning -->
        <div
          v-if="selfHostedBilling?.subscription?.blocked"
          class="bg-red-50 border-l-4 border-red-500 p-4 rounded mb-4"
        >
          <div class="flex items-start">
            <div class="flex-shrink-0">
              <span class="text-red-500 font-bold text-lg">{{ '⚠️' }}</span>
            </div>
            <div class="ml-3">
              <h3 class="text-sm font-medium text-red-800">
                {{ $t('BILLING_SETTINGS.SELF_HOSTED.BLOCKED_TITLE') }}
              </h3>
              <p class="text-xs text-red-700 mt-1">
                {{ $t('BILLING_SETTINGS.SELF_HOSTED.BLOCKED_DESCRIPTION') }}
              </p>
              <div class="mt-3">
                <ButtonV4 sm solid red @click="openStripePortal">
                  {{ $t('BILLING_SETTINGS.SELF_HOSTED.PAY_PENDING') }}
                </ButtonV4>
              </div>
            </div>
          </div>
        </div>

        <!-- Subscription Overview -->
        <BillingCard
          :title="$t('BILLING_SETTINGS.SELF_HOSTED.ACTIVE_SUB')"
          :description="$t('BILLING_SETTINGS.SELF_HOSTED.ACTIVE_SUB_DESC')"
        >
          <template #action>
            <div
              v-if="
                selfHostedBilling?.subscription?.status &&
                selfHostedBilling.subscription.status !== 'none'
              "
            >
              <ButtonV4 sm solid blue @click="openStripePortal">
                {{ $t('BILLING_SETTINGS.SELF_HOSTED.MANAGE_STRIPE') }}
              </ButtonV4>
            </div>
          </template>

          <div
            v-if="
              selfHostedBilling?.subscription &&
              selfHostedBilling.subscription.status !== 'none'
            "
            class="grid lg:grid-cols-4 sm:grid-cols-2 grid-cols-1 gap-4 py-2"
          >
            <DetailItem
              :label="$t('BILLING_SETTINGS.SELF_HOSTED.PLAN_CONTRATADO')"
              :value="
                selfHostedBilling.subscription.plan_name ||
                $t('BILLING_SETTINGS.SELF_HOSTED.CUSTOM_PLAN')
              "
            />
            <DetailItem
              :label="$t('BILLING_SETTINGS.SELF_HOSTED.VALOR_MENSAL')"
              :value="
                formatCurrency(
                  selfHostedBilling.subscription.amount,
                  selfHostedBilling.subscription.currency
                )
              "
            />
            <DetailItem
              :label="$t('BILLING_SETTINGS.SELF_HOSTED.PROXIMO_VENCIMENTO')"
              :value="
                formatDate(selfHostedBilling.subscription.current_period_end)
              "
            />
            <DetailItem
              :label="$t('BILLING_SETTINGS.SELF_HOSTED.STATUS_ASSINATURA')"
              :value="translateStatus(selfHostedBilling.subscription.status)"
              :class="statusColorClass(selfHostedBilling.subscription.status)"
            />
          </div>
          <div
            v-else
            class="py-4 text-center border border-dashed border-n-weak rounded"
          >
            <p class="text-sm text-n-mild mb-3">
              {{ $t('BILLING_SETTINGS.SELF_HOSTED.NO_SUB') }}
            </p>
          </div>
        </BillingCard>

        <!-- Plans Selection (if not subscribed) -->
        <BillingCard
          v-if="
            !selfHostedBilling?.subscription ||
            selfHostedBilling.subscription.status === 'none'
          "
          :title="$t('BILLING_SETTINGS.SELF_HOSTED.AVAILABLE_PLANS')"
          :description="$t('BILLING_SETTINGS.SELF_HOSTED.AVAILABLE_PLANS_DESC')"
        >
          <div
            v-if="
              selfHostedBilling?.plans && selfHostedBilling.plans.length > 0
            "
            class="grid md:grid-cols-3 gap-4 py-2"
          >
            <div
              v-for="plan in selfHostedBilling.plans"
              :key="plan.stripe_price_id"
              class="border border-n-weak p-4 rounded flex flex-col justify-between hover:border-blue-500 transition-colors"
            >
              <div>
                <h4 class="text-base font-bold text-n-most mb-2">
                  {{ plan.name }}
                </h4>
                <div class="text-2xl font-extrabold text-blue-600 mb-4">
                  {{ formatCurrency(plan.amount, plan.currency)
                  }}<span class="text-xs font-normal text-n-mild">{{
                    $t('BILLING_SETTINGS.SELF_HOSTED.MES')
                  }}</span>
                </div>
              </div>
              <ButtonV4
                solid
                blue
                block
                @click="checkoutPlan(plan.stripe_price_id)"
              >
                {{ $t('BILLING_SETTINGS.SELF_HOSTED.ASSINAR_AGORA') }}
              </ButtonV4>
            </div>
          </div>
          <div v-else class="py-4 text-center text-sm text-n-mild">
            {{ $t('BILLING_SETTINGS.SELF_HOSTED.NO_PLANS_AVAILABLE') }}
          </div>
        </BillingCard>

        <!-- Invoices List -->
        <BillingCard
          v-if="
            selfHostedBilling?.invoices && selfHostedBilling.invoices.length > 0
          "
          :title="$t('BILLING_SETTINGS.SELF_HOSTED.INVOICES_TITLE')"
          :description="$t('BILLING_SETTINGS.SELF_HOSTED.INVOICES_DESC')"
        >
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-n-weak text-sm">
              <thead>
                <tr>
                  <th class="px-4 py-2 text-left font-semibold text-n-most">
                    {{ $t('BILLING_SETTINGS.SELF_HOSTED.ID_FATURA') }}
                  </th>
                  <th class="px-4 py-2 text-left font-semibold text-n-most">
                    {{ $t('BILLING_SETTINGS.SELF_HOSTED.DATA') }}
                  </th>
                  <th class="px-4 py-2 text-left font-semibold text-n-most">
                    {{ $t('BILLING_SETTINGS.SELF_HOSTED.VALOR') }}
                  </th>
                  <th class="px-4 py-2 text-left font-semibold text-n-most">
                    {{ $t('BILLING_SETTINGS.SELF_HOSTED.STATUS') }}
                  </th>
                  <th class="px-4 py-2 text-left font-semibold text-n-most">
                    {{ $t('BILLING_SETTINGS.SELF_HOSTED.COMPROVANTE') }}
                  </th>
                  <th class="px-4 py-2 text-left font-semibold text-n-most">
                    {{ $t('BILLING_SETTINGS.SELF_HOSTED.NOTA_FISCAL') }}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-n-weak">
                <tr
                  v-for="invoice in selfHostedBilling.invoices"
                  :key="invoice.id"
                >
                  <td class="px-4 py-3 text-n-most font-mono text-xs">
                    {{ invoice.stripe_invoice_id || `MAN-${invoice.id}` }}
                  </td>
                  <td class="px-4 py-3 text-n-mild">
                    {{ formatDate(invoice.created_at) }}
                  </td>
                  <td class="px-4 py-3 text-n-most font-medium">
                    {{ formatCurrency(invoice.amount, invoice.currency) }}
                  </td>
                  <td class="px-4 py-3">
                    <span
                      class="inline-block px-2 py-0.5 rounded text-xs font-medium"
                      :class="invoiceStatusClass(invoice.status)"
                    >
                      {{ translateInvoiceStatus(invoice.status) }}
                    </span>
                  </td>
                  <td class="px-4 py-3">
                    <a
                      v-if="invoice.invoice_pdf"
                      :href="invoice.invoice_pdf"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-blue-600 hover:underline flex items-center gap-1 text-xs"
                    >
                      📥 {{ $t('BILLING_SETTINGS.SELF_HOSTED.RECIBO_STRIPE') }}
                    </a>
                    <span v-else class="text-xs text-n-light">-</span>
                  </td>
                  <td class="px-4 py-3">
                    <div
                      v-if="invoice.files && invoice.files.length > 0"
                      class="flex flex-col gap-1"
                    >
                      <a
                        v-for="file in invoice.files"
                        :key="file.id"
                        :href="file.url"
                        download
                        class="text-emerald-600 hover:underline flex items-center gap-1 text-xs"
                      >
                        📄 {{ file.filename }}
                      </a>
                    </div>
                    <span v-else class="text-xs text-n-light">{{
                      $t('BILLING_SETTINGS.SELF_HOSTED.SEM_ANEXOS')
                    }}</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </BillingCard>
      </section>

      <PurchaseCreditsModal
        ref="purchaseCreditsModalRef"
        @success="handleTopupSuccess"
      />
    </template>
  </SettingsLayout>
</template>
