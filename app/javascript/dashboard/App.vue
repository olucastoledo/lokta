<script>
import { mapGetters } from 'vuex';
import LoadingState from './components/widgets/LoadingState.vue';
import NetworkNotification from './components/NetworkNotification.vue';
import UpdateBanner from './components/app/UpdateBanner.vue';
import StatusBanner from './components/app/StatusBanner.vue';
import PaymentPendingBanner from './components/app/PaymentPendingBanner.vue';
import PendingEmailVerificationBanner from './components/app/PendingEmailVerificationBanner.vue';
import vueActionCable from './helper/actionCable';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import WootSnackbarBox from './components/SnackbarContainer.vue';
import { setColorTheme } from './helper/themeHelper';
import { isOnOnboardingView } from 'v3/helpers/RouteHelper';
import { useAccount } from 'dashboard/composables/useAccount';
import { useFontSize } from 'dashboard/composables/useFontSize';
import {
  registerSubscription,
  verifyServiceWorkerExistence,
} from './helper/pushHelper';
import ReconnectService from 'dashboard/helper/ReconnectService';
import { useUISettings } from 'dashboard/composables/useUISettings';

export default {
  name: 'App',

  components: {
    LoadingState,
    NetworkNotification,
    UpdateBanner,
    StatusBanner,
    PaymentPendingBanner,
    WootSnackbarBox,
    PendingEmailVerificationBanner,
  },
  setup() {
    const router = useRouter();
    const store = useStore();
    const { accountId } = useAccount();
    // Use the font size composable (it automatically sets up the watcher)
    const { currentFontSize } = useFontSize();
    const { uiSettings } = useUISettings();

    return {
      router,
      store,
      currentAccountId: accountId,
      currentFontSize,
      uiSettings,
    };
  },
  data() {
    return {
      latestChatwootVersion: null,
      reconnectService: null,
      showTermsModal: false,
      showAnnouncementModal: false,
      termsData: null,
      announcementData: null,
      hasCheckedTerms: false,
      isSubmittingTerms: false,
      isSubmittingAnnouncement: false,
    };
  },
  computed: {
    ...mapGetters({
      getAccount: 'accounts/getAccount',
      isRTL: 'accounts/isRTL',
      currentUser: 'getCurrentUser',
      authUIFlags: 'getAuthUIFlags',
    }),
    hideOnOnboardingView() {
      return !isOnOnboardingView(this.$route);
    },
  },

  watch: {
    currentAccountId: {
      immediate: true,
      handler() {
        if (this.currentAccountId) {
          this.initializeAccount();
        }
      },
    },
  },
  mounted() {
    this.initializeColorTheme();
    this.listenToThemeChanges();
    // If user locale is set, use it; otherwise use account locale
    this.setLocale(
      this.uiSettings?.locale || window.chatwootConfig.selectedLocale
    );
  },
  unmounted() {
    if (this.reconnectService) {
      this.reconnectService.disconnect();
    }
  },
  methods: {
    initializeColorTheme() {
      setColorTheme(window.matchMedia('(prefers-color-scheme: dark)').matches);
    },
    listenToThemeChanges() {
      const mql = window.matchMedia('(prefers-color-scheme: dark)');
      mql.onchange = e => setColorTheme(e.matches);
    },
    setLocale(locale) {
      if (locale) {
        this.$root.$i18n.locale = locale;
      }
    },
    async initializeAccount() {
      await this.$store.dispatch('accounts/get');
      this.$store.dispatch('setActiveAccount', {
        accountId: this.currentAccountId,
      });
      const account = this.getAccount(this.currentAccountId);
      const { locale, latest_chatwoot_version: latestChatwootVersion } =
        account;
      const { pubsub_token: pubsubToken } = this.currentUser || {};
      // If user locale is set, use it; otherwise use account locale
      this.setLocale(this.uiSettings?.locale || locale);
      this.latestChatwootVersion = latestChatwootVersion;
      vueActionCable.init(this.store, pubsubToken);
      this.reconnectService = new ReconnectService(this.store, this.router);
      window.reconnectService = this.reconnectService;

      verifyServiceWorkerExistence(registration =>
        registration.pushManager.getSubscription().then(subscription => {
          if (subscription) {
            registerSubscription();
          }
        })
      );

      await this.checkTermsAndAnnouncements();
    },
    async checkTermsAndAnnouncements() {
      try {
        const { data } = await window.axios.get(
          '/api/v1/profile/terms_and_announcements'
        );
        this.termsData = data.terms_of_service;
        this.announcementData = data.custom_announcement;

        if (
          this.termsData &&
          !this.termsData.accepted &&
          this.termsData.content
        ) {
          this.showTermsModal = true;
        } else if (
          this.announcementData &&
          this.announcementData.active &&
          !this.announcementData.dismissed &&
          this.announcementData.content
        ) {
          this.showAnnouncementModal = true;
        }
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error('Failed to fetch terms/announcements', error);
      }
    },
    async acceptTerms() {
      if (!this.hasCheckedTerms || !this.termsData) return;
      this.isSubmittingTerms = true;
      try {
        await window.axios.post('/api/v1/profile/accept_terms', {
          terms_version: this.termsData.version,
        });
        this.showTermsModal = false;

        if (
          this.announcementData &&
          this.announcementData.active &&
          !this.announcementData.dismissed &&
          this.announcementData.content
        ) {
          this.showAnnouncementModal = true;
        }
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error('Failed to accept terms', error);
      } finally {
        this.isSubmittingTerms = false;
      }
    },
    async dismissAnnouncement() {
      if (!this.announcementData) return;
      this.isSubmittingAnnouncement = true;
      try {
        await window.axios.post('/api/v1/profile/dismiss_announcement', {
          announcement_version: this.announcementData.version,
        });
        this.showAnnouncementModal = false;
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error('Failed to dismiss announcement', error);
      } finally {
        this.isSubmittingAnnouncement = false;
      }
    },
  },
};
</script>

<template>
  <div
    v-if="!authUIFlags.isFetching"
    id="app"
    class="flex flex-col w-full h-screen min-h-0 bg-n-background"
    :dir="isRTL ? 'rtl' : 'ltr'"
  >
    <UpdateBanner :latest-chatwoot-version="latestChatwootVersion" />
    <StatusBanner />
    <template v-if="currentAccountId">
      <PendingEmailVerificationBanner v-if="hideOnOnboardingView" />
      <PaymentPendingBanner v-if="hideOnOnboardingView" />
    </template>
    <router-view v-slot="{ Component }">
      <transition name="fade" mode="out-in">
        <component :is="Component" />
      </transition>
    </router-view>
    <WootSnackbarBox />
    <NetworkNotification />

    <!-- Terms of Service Modal -->
    <div
      v-if="showTermsModal && termsData"
      class="fixed inset-0 z-[9999] flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm"
    >
      <div
        class="bg-white dark:bg-slate-955 rounded-2xl border border-slate-200 dark:border-slate-800 shadow-2xl max-w-lg w-full overflow-hidden transform transition-all duration-300 flex flex-col max-h-[80vh]"
      >
        <!-- Header -->
        <div class="p-6 pb-4 border-b border-slate-100 dark:border-slate-800">
          <h3
            class="text-xl font-semibold text-slate-900 dark:text-white flex items-center gap-2"
          >
            {{ $t('TERMS_AND_ANNOUNCEMENTS.TOS_HEADER') }}
          </h3>
        </div>
        <!-- Body -->
        <div
          class="p-6 overflow-y-auto text-sm text-slate-600 dark:text-slate-300 leading-relaxed flex-1"
        >
          <div
            class="prose dark:prose-invert max-w-none"
            v-html="termsData.content"
          />
        </div>
        <!-- Footer -->
        <div
          class="p-6 pt-4 border-t border-slate-100 dark:border-slate-800 bg-slate-50/50 dark:bg-slate-900/50 flex flex-col gap-4"
        >
          <label class="flex items-start gap-3 cursor-pointer">
            <input
              v-model="hasCheckedTerms"
              type="checkbox"
              class="mt-1 h-4 w-4 rounded border-slate-300 text-woot-600 focus:ring-woot-500 cursor-pointer"
            />
            <span
              class="text-xs text-slate-600 dark:text-slate-400 select-none"
            >
              {{ $t('TERMS_AND_ANNOUNCEMENTS.TOS_CHECKBOX') }}
            </span>
          </label>
          <button
            :disabled="!hasCheckedTerms || isSubmittingTerms"
            class="w-full flex justify-center py-2.5 px-4 border border-transparent rounded-lg shadow-sm text-sm font-medium text-white bg-woot-600 hover:bg-woot-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-woot-500 disabled:opacity-50 disabled:cursor-not-allowed transition-all duration-200"
            @click="acceptTerms"
          >
            {{
              isSubmittingTerms
                ? $t('TERMS_AND_ANNOUNCEMENTS.SUBMITTING')
                : $t('TERMS_AND_ANNOUNCEMENTS.TOS_ACCEPT')
            }}
          </button>
        </div>
      </div>
    </div>

    <!-- Custom Announcement Modal -->
    <div
      v-if="showAnnouncementModal && announcementData"
      class="fixed inset-0 z-[9999] flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm"
    >
      <div
        class="bg-white dark:bg-slate-955 rounded-2xl border border-slate-200 dark:border-slate-800 shadow-2xl max-w-lg w-full overflow-hidden transform transition-all duration-300 flex flex-col max-h-[80vh]"
      >
        <!-- Header -->
        <div
          class="p-6 pb-4 border-b border-slate-100 dark:border-slate-800 flex justify-between items-center"
        >
          <h3
            class="text-xl font-semibold text-slate-900 dark:text-white flex items-center gap-2"
          >
            {{ $t('TERMS_AND_ANNOUNCEMENTS.ANNOUNCEMENT_HEADER') }}
          </h3>
        </div>
        <!-- Body -->
        <div
          class="p-6 overflow-y-auto text-sm text-slate-600 dark:text-slate-300 leading-relaxed flex-1"
        >
          <div
            class="prose dark:prose-invert max-w-none"
            v-html="announcementData.content"
          />
        </div>
        <!-- Footer -->
        <div
          class="p-6 pt-4 border-t border-slate-100 dark:border-slate-800 bg-slate-50/50 dark:bg-slate-900/50 flex gap-3 justify-end"
        >
          <button
            :disabled="isSubmittingAnnouncement"
            class="px-4 py-2 border border-slate-300 dark:border-slate-700 rounded-lg text-sm font-medium text-slate-700 dark:text-slate-300 bg-white dark:bg-slate-800 hover:bg-slate-50 dark:hover:bg-slate-700 transition-all duration-200"
            @click="dismissAnnouncement"
          >
            {{ $t('TERMS_AND_ANNOUNCEMENTS.ANNOUNCEMENT_CLOSE') }}
          </button>
          <a
            v-if="
              announcementData.button_text &&
              announcementData.button_link &&
              announcementData.button_link !== 'https://'
            "
            :href="announcementData.button_link"
            target="_blank"
            rel="noopener noreferrer"
            class="px-4 py-2 border border-transparent rounded-lg shadow-sm text-sm font-medium text-white bg-woot-600 hover:bg-woot-700 transition-all duration-200 flex items-center justify-center"
            @click="dismissAnnouncement"
          >
            {{ announcementData.button_text }}
          </a>
        </div>
      </div>
    </div>
  </div>
  <LoadingState v-else />
</template>

<style lang="scss">
@import './assets/scss/app';

.v-popper--theme-tooltip .v-popper__inner {
  background: black !important;
  font-size: 0.75rem;
  padding: 4px 8px !important;
  border-radius: 6px;
  font-weight: 400;
}

.v-popper--theme-tooltip .v-popper__arrow-container {
  display: none;
}
</style>
