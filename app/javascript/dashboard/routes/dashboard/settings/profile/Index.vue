<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useFontSize } from 'dashboard/composables/useFontSize';
import { useBranding } from 'shared/composables/useBranding';
import { clearCookiesOnLogout } from 'dashboard/store/utils/api.js';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import { parseBoolean } from '@chatwoot/utils';
import UserProfilePicture from './UserProfilePicture.vue';
import UserBasicDetails from './UserBasicDetails.vue';
import MessageSignature from './MessageSignature.vue';
import FontSize from './FontSize.vue';
import UserLanguageSelect from './UserLanguageSelect.vue';
import ChangePassword from './ChangePassword.vue';
import NotificationPreferences from './NotificationPreferences.vue';
import AudioNotifications from './AudioNotifications.vue';
import SectionLayout from '../account/components/SectionLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import AccessToken from './AccessToken.vue';
import MfaSettingsCard from './MfaSettingsCard.vue';
import Policy from 'dashboard/components/policy.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from 'dashboard/constants/permissions.js';

export default {
  components: {
    MessageSignature,
    SectionLayout,
    FontSize,
    UserLanguageSelect,
    UserProfilePicture,
    Policy,
    UserBasicDetails,
    RadioCard,
    ChangePassword,
    NotificationPreferences,
    AudioNotifications,
    AccessToken,
    MfaSettingsCard,
    BaseSettingsHeader,
  },
  setup() {
    const { isEditorHotKeyEnabled, updateUISettings } = useUISettings();
    const { currentFontSize, updateFontSize } = useFontSize();
    const { replaceInstallationName } = useBranding();

    return {
      currentFontSize,
      updateFontSize,
      isEditorHotKeyEnabled,
      updateUISettings,
      replaceInstallationName,
    };
  },
  data() {
    return {
      avatarFile: '',
      avatarUrl: '',
      name: '',
      displayName: '',
      email: '',
      messageSignature: '',
      hotKeys: [
        {
          key: 'enter',
          title: this.$t(
            'PROFILE_SETTINGS.FORM.SEND_MESSAGE.CARD.ENTER_KEY.HEADING'
          ),
          description: this.$t(
            'PROFILE_SETTINGS.FORM.SEND_MESSAGE.CARD.ENTER_KEY.CONTENT'
          ),
          lightImage: '/assets/images/dashboard/profile/hot-key-enter.svg',
          darkImage: '/assets/images/dashboard/profile/hot-key-enter-dark.svg',
        },
        {
          key: 'cmd_enter',
          title: this.$t(
            'PROFILE_SETTINGS.FORM.SEND_MESSAGE.CARD.CMD_ENTER_KEY.HEADING'
          ),
          description: this.$t(
            'PROFILE_SETTINGS.FORM.SEND_MESSAGE.CARD.CMD_ENTER_KEY.CONTENT'
          ),
          lightImage: '/assets/images/dashboard/profile/hot-key-ctrl-enter.svg',
          darkImage:
            '/assets/images/dashboard/profile/hot-key-ctrl-enter-dark.svg',
        },
      ],
      notificationPermissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
      audioNotificationPermissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
      termsHistory: {},
      userTermsLogs: [],
      allUsersTermsLogs: [],
      selectedTermVersion: null,
      selectedTermContent: '',
      showTermModal: false,
    };
  },
  computed: {
    ...mapGetters({
      currentUser: 'getCurrentUser',
      currentUserId: 'getCurrentUserID',
      globalConfig: 'globalConfig/get',
    }),
    isMfaEnabled() {
      return parseBoolean(window.chatwootConfig?.isMfaEnabled);
    },
  },
  mounted() {
    if (this.currentUserId) {
      this.initializeUser();
      this.fetchTermsLogs();
    }
  },
  methods: {
    initializeUser() {
      this.name = this.currentUser.name;
      this.email = this.currentUser.email;
      this.avatarUrl = this.currentUser.avatar_url;
      this.displayName = this.currentUser.display_name;
      this.messageSignature = this.currentUser.message_signature;
    },
    async dispatchUpdate(payload, successMessage, errorMessage) {
      let alertMessage = '';
      try {
        await this.$store.dispatch('updateProfile', payload);
        alertMessage = successMessage;

        return true; // return the value so that the status can be known
      } catch (error) {
        alertMessage = parseAPIErrorResponse(error) || errorMessage;

        return false; // return the value so that the status can be known
      } finally {
        useAlert(alertMessage);
      }
    },
    async updateProfile(userAttributes) {
      const { name, email, displayName } = userAttributes;
      const hasEmailChanged = this.currentUser.email !== email;
      this.name = name || this.name;
      this.email = email || this.email;
      this.displayName = displayName || this.displayName;

      const updatePayload = {
        name: this.name,
        email: this.email,
        displayName: this.displayName,
        avatar: this.avatarFile,
      };

      const success = await this.dispatchUpdate(
        updatePayload,
        hasEmailChanged
          ? this.$t('PROFILE_SETTINGS.AFTER_EMAIL_CHANGED')
          : this.$t('PROFILE_SETTINGS.UPDATE_SUCCESS'),
        this.$t('RESET_PASSWORD.API.ERROR_MESSAGE')
      );

      if (hasEmailChanged && success) clearCookiesOnLogout();
    },
    async updateSignature(signature) {
      const payload = { message_signature: signature };
      let successMessage = this.$t(
        'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.API_SUCCESS'
      );
      let errorMessage = this.$t(
        'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.API_ERROR'
      );

      await this.dispatchUpdate(payload, successMessage, errorMessage);
    },
    updateProfilePicture({ file, url }) {
      this.avatarFile = file;
      this.avatarUrl = url;
    },
    async deleteProfilePicture() {
      try {
        await this.$store.dispatch('deleteAvatar');
        this.avatarUrl = '';
        this.avatarFile = '';
        useAlert(this.$t('PROFILE_SETTINGS.AVATAR_DELETE_SUCCESS'));
      } catch (error) {
        useAlert(this.$t('PROFILE_SETTINGS.AVATAR_DELETE_FAILED'));
      }
    },
    toggleHotKey(key) {
      this.hotKeys = this.hotKeys.map(hotKey =>
        hotKey.key === key ? { ...hotKey, active: !hotKey.active } : hotKey
      );
      this.updateUISettings({ editor_message_key: key });
      useAlert(this.$t('PROFILE_SETTINGS.FORM.SEND_MESSAGE.UPDATE_SUCCESS'));
    },
    async onCopyToken(value) {
      await copyTextToClipboard(value);
      useAlert(this.$t('COMPONENTS.CODE.COPY_SUCCESSFUL'));
    },
    async resetAccessToken() {
      const success = await this.$store.dispatch('resetAccessToken');
      if (success) {
        useAlert(this.$t('PROFILE_SETTINGS.FORM.ACCESS_TOKEN.RESET_SUCCESS'));
      } else {
        useAlert(this.$t('PROFILE_SETTINGS.FORM.ACCESS_TOKEN.RESET_ERROR'));
      }
    },
    async fetchTermsLogs() {
      try {
        const response = await window.axios.get(
          '/api/v1/profile/terms_acceptance_logs'
        );
        this.termsHistory = response.data.history || {};
        this.userTermsLogs = response.data.user_logs || [];
        this.allUsersTermsLogs = response.data.all_users_logs || [];
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error('Failed to fetch terms logs', error);
      }
    },
    viewTermContent(version) {
      this.selectedTermVersion = version;
      const historyItem = this.termsHistory[version];
      this.selectedTermContent = historyItem ? historyItem.content : '';
      this.showTermModal = true;
    },
    closeTermModal() {
      this.showTermModal = false;
      this.selectedTermVersion = null;
      this.selectedTermContent = '';
    },
    formatDate(dateStr) {
      if (!dateStr) return '';
      try {
        const date = new Date(dateStr);
        return date.toLocaleString();
      } catch (e) {
        return dateStr;
      }
    },
  },
};
</script>

<template>
  <div class="grid max-w-2xl ltr:mr-auto rtl:ml-auto">
    <BaseSettingsHeader :title="$t('PROFILE_SETTINGS.TITLE')" description="" />
    <SectionLayout title="" description="" class="!pt-0">
      <div class="flex flex-col gap-6">
        <UserProfilePicture
          :src="avatarUrl"
          :name="name"
          @change="updateProfilePicture"
          @delete="deleteProfilePicture"
        />
        <UserBasicDetails
          :name="name"
          :display-name="displayName"
          :email="email"
          :email-enabled="!globalConfig.disableUserProfileUpdate"
          @update-user="updateProfile"
        />
      </div>
    </SectionLayout>
    <SectionLayout
      with-border
      :title="$t('PROFILE_SETTINGS.FORM.INTERFACE_SECTION.TITLE')"
      :description="
        replaceInstallationName(
          $t('PROFILE_SETTINGS.FORM.INTERFACE_SECTION.NOTE')
        )
      "
    >
      <div class="flex flex-col gap-6 items-start">
        <FontSize
          :value="currentFontSize"
          :label="$t('PROFILE_SETTINGS.FORM.INTERFACE_SECTION.FONT_SIZE.TITLE')"
          :description="
            $t('PROFILE_SETTINGS.FORM.INTERFACE_SECTION.FONT_SIZE.NOTE')
          "
          @change="updateFontSize"
        />
        <UserLanguageSelect
          :label="$t('PROFILE_SETTINGS.FORM.INTERFACE_SECTION.LANGUAGE.TITLE')"
          :description="
            $t('PROFILE_SETTINGS.FORM.INTERFACE_SECTION.LANGUAGE.NOTE')
          "
        />
      </div>
    </SectionLayout>
    <SectionLayout
      with-border
      :title="$t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.TITLE')"
      :description="$t('PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.NOTE')"
    >
      <MessageSignature
        :message-signature="messageSignature"
        @update-signature="updateSignature"
      />
    </SectionLayout>
    <SectionLayout
      with-border
      :title="$t('PROFILE_SETTINGS.FORM.SEND_MESSAGE.TITLE')"
      :description="$t('PROFILE_SETTINGS.FORM.SEND_MESSAGE.NOTE')"
    >
      <div
        class="flex flex-col justify-between w-full gap-5 sm:gap-4 sm:flex-row"
      >
        <RadioCard
          v-for="hotKey in hotKeys"
          :id="hotKey.key"
          :key="hotKey.key"
          :label="hotKey.title"
          :description="hotKey.description"
          :is-active="isEditorHotKeyEnabled(hotKey.key)"
          class="sm:flex-1"
          @select="toggleHotKey"
        >
          <img
            :src="hotKey.lightImage"
            :alt="`Light themed image for ${hotKey.title}`"
            class="block object-cover w-full dark:hidden"
          />
          <img
            :src="hotKey.darkImage"
            :alt="`Dark themed image for ${hotKey.title}`"
            class="hidden object-cover w-full dark:block"
          />
        </RadioCard>
      </div>
    </SectionLayout>
    <SectionLayout
      v-if="!globalConfig.disableUserProfileUpdate"
      with-border
      :title="$t('PROFILE_SETTINGS.FORM.PASSWORD_SECTION.TITLE')"
      description=""
    >
      <ChangePassword />
    </SectionLayout>
    <SectionLayout
      v-if="isMfaEnabled"
      with-border
      :title="$t('PROFILE_SETTINGS.FORM.SECURITY_SECTION.TITLE')"
      :description="$t('PROFILE_SETTINGS.FORM.SECURITY_SECTION.NOTE')"
    >
      <MfaSettingsCard />
    </SectionLayout>
    <Policy :permissions="audioNotificationPermissions">
      <SectionLayout
        with-border
        :title="$t('PROFILE_SETTINGS.FORM.AUDIO_NOTIFICATIONS_SECTION.TITLE')"
        :description="
          $t('PROFILE_SETTINGS.FORM.AUDIO_NOTIFICATIONS_SECTION.NOTE')
        "
      >
        <AudioNotifications />
      </SectionLayout>
    </Policy>
    <Policy :permissions="notificationPermissions">
      <SectionLayout
        with-border
        :title="$t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.TITLE')"
        description=""
      >
        <NotificationPreferences />
      </SectionLayout>
    </Policy>
    <SectionLayout
      with-border
      :title="$t('PROFILE_SETTINGS.FORM.ACCESS_TOKEN.TITLE')"
      :description="
        replaceInstallationName($t('PROFILE_SETTINGS.FORM.ACCESS_TOKEN.NOTE'))
      "
    >
      <AccessToken
        :value="currentUser.access_token"
        @on-copy="onCopyToken"
        @on-reset="resetAccessToken"
      />
    </SectionLayout>

    <SectionLayout
      with-border
      :title="$t('PROFILE_SETTINGS.FORM.TERMS_LOGS.TITLE')"
      :description="$t('PROFILE_SETTINGS.FORM.TERMS_LOGS.NOTE')"
    >
      <div class="w-full flex flex-col gap-6">
        <!-- Tabela do Usuário Logado -->
        <div class="overflow-x-auto">
          <table
            class="min-w-full divide-y divide-slate-100 dark:divide-slate-800"
          >
            <thead>
              <tr
                class="text-left text-xs font-semibold text-slate-500 uppercase tracking-wider"
              >
                <th class="py-3 px-4">
                  {{ $t('PROFILE_SETTINGS.FORM.TERMS_LOGS.TABLE.VERSION') }}
                </th>
                <th class="py-3 px-4">
                  {{ $t('PROFILE_SETTINGS.FORM.TERMS_LOGS.TABLE.ACCEPTED_AT') }}
                </th>
                <th class="py-3 px-4" />
              </tr>
            </thead>
            <tbody
              class="divide-y divide-slate-100 dark:divide-slate-800 text-sm"
            >
              <tr v-for="log in userTermsLogs" :key="log.version">
                <td class="py-3 px-4 font-medium">{{ log.version }}</td>
                <td class="py-3 px-4 text-slate-600 dark:text-slate-400">
                  {{ formatDate(log.accepted_at) }}
                </td>
                <td class="py-3 px-4 text-right">
                  <woot-button
                    variant="link"
                    size="small"
                    @click="viewTermContent(log.version)"
                  >
                    {{
                      $t('PROFILE_SETTINGS.FORM.TERMS_LOGS.TABLE.ACTION_VIEW')
                    }}
                  </woot-button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Seção do Administrador (Lista todos os usuários da conta) -->
        <div
          v-if="
            currentUser.role === 'administrator' && allUsersTermsLogs.length
          "
          class="mt-4 border-t border-slate-100 dark:border-slate-800 pt-6"
        >
          <h4 class="text-base font-semibold mb-2">
            {{ $t('PROFILE_SETTINGS.FORM.TERMS_LOGS.ALL_USERS_TITLE') }}
          </h4>
          <p class="text-sm text-slate-600 dark:text-slate-400 mb-4">
            {{ $t('PROFILE_SETTINGS.FORM.TERMS_LOGS.ALL_USERS_NOTE') }}
          </p>
          <div class="overflow-x-auto">
            <table
              class="min-w-full divide-y divide-slate-100 dark:divide-slate-800"
            >
              <thead>
                <tr
                  class="text-left text-xs font-semibold text-slate-500 uppercase tracking-wider"
                >
                  <th class="py-3 px-4">
                    {{ $t('PROFILE_SETTINGS.FORM.TERMS_LOGS.TABLE.USER_NAME') }}
                  </th>
                  <th class="py-3 px-4">
                    {{
                      $t('PROFILE_SETTINGS.FORM.TERMS_LOGS.TABLE.USER_EMAIL')
                    }}
                  </th>
                  <th class="py-3 px-4">
                    {{ $t('PROFILE_SETTINGS.FORM.TERMS_LOGS.TABLE.VERSION') }}
                  </th>
                  <th class="py-3 px-4">
                    {{
                      $t('PROFILE_SETTINGS.FORM.TERMS_LOGS.TABLE.ACCEPTED_AT')
                    }}
                  </th>
                  <th class="py-3 px-4" />
                </tr>
              </thead>
              <tbody
                class="divide-y divide-slate-100 dark:divide-slate-800 text-sm"
              >
                <tr v-for="(log, idx) in allUsersTermsLogs" :key="idx">
                  <td class="py-3 px-4 font-medium">{{ log.user_name }}</td>
                  <td class="py-3 px-4 text-slate-600 dark:text-slate-400">
                    {{ log.user_email }}
                  </td>
                  <td class="py-3 px-4">{{ log.version }}</td>
                  <td class="py-3 px-4 text-slate-600 dark:text-slate-400">
                    {{ formatDate(log.accepted_at) }}
                  </td>
                  <td class="py-3 px-4 text-right">
                    <woot-button
                      variant="link"
                      size="small"
                      @click="viewTermContent(log.version)"
                    >
                      {{
                        $t('PROFILE_SETTINGS.FORM.TERMS_LOGS.TABLE.ACTION_VIEW')
                      }}
                    </woot-button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </SectionLayout>
  </div>

  <!-- Modal para Visualizar o Texto dos Termos -->
  <div
    v-if="showTermModal"
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900 bg-opacity-50"
    @click.self="closeTermModal"
  >
    <div
      class="relative w-full max-w-lg bg-white dark:bg-slate-950 rounded-xl shadow-xl overflow-hidden flex flex-col max-h-[85vh]"
    >
      <div
        class="flex items-center justify-between px-6 py-4 border-b border-slate-100 dark:border-slate-800"
      >
        <h3 class="text-lg font-bold text-slate-900 dark:text-white">
          {{
            $t('PROFILE_SETTINGS.FORM.TERMS_LOGS.TABLE.MODAL_TITLE', {
              version: selectedTermVersion,
            })
          }}
        </h3>
        <woot-button variant="clear" size="small" @click="closeTermModal">
          <fluent-icon icon="dismiss" :size="16" />
        </woot-button>
      </div>
      <div
        class="flex-1 overflow-y-auto px-6 py-4 prose dark:prose-invert max-w-none text-slate-700 dark:text-slate-300"
      >
        <div v-html="selectedTermContent" />
      </div>
      <div
        class="flex justify-end px-6 py-4 border-t border-slate-100 dark:border-slate-800 bg-slate-50 dark:bg-slate-900/50"
      >
        <woot-button variant="clear" @click="closeTermModal">
          {{ $t('PROFILE_SETTINGS.FORM.TERMS_LOGS.TABLE.CLOSE') }}
        </woot-button>
      </div>
    </div>
  </div>
</template>
