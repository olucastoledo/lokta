# == Schema Information
#
# Table name: installation_configs
#
#  id               :bigint           not null, primary key
#  locked           :boolean          default(TRUE), not null
#  name             :string           not null
#  serialized_value :jsonb            not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_installation_configs_on_name                 (name) UNIQUE
#  index_installation_configs_on_name_and_created_at  (name,created_at) UNIQUE
#
class InstallationConfig < ApplicationRecord
  CAPTAIN_LLM_CONFIG_KEYS = %w[
    CAPTAIN_OPEN_AI_API_KEY
    CAPTAIN_OPEN_AI_ENDPOINT
    CAPTAIN_OPEN_AI_MODEL
  ].freeze

  RESTART_REQUIRED_CONFIG_KEYS = (CAPTAIN_LLM_CONFIG_KEYS + %w[
    LANGFUSE_BASE_URL
    LANGFUSE_PUBLIC_KEY
    LANGFUSE_SECRET_KEY
    OTEL_PROVIDER
  ]).freeze

  # https://stackoverflow.com/questions/72970170/upgrading-to-rails-6-1-6-1-causes-psychdisallowedclass-tried-to-load-unspecif
  # https://discuss.rubyonrails.org/t/cve-2022-32224-possible-rce-escalation-bug-with-serialized-columns-in-active-record/81017
  # FIX ME : fixes breakage of installation config. we need to migrate.
  # Fix configuration in application.rb
  serialize :serialized_value, coder: YAML, type: ActiveSupport::HashWithIndifferentAccess, default: {}.with_indifferent_access

  before_validation :set_lock
  validates :name, presence: true
  validate :saml_sso_users_check, if: -> { name == 'ENABLE_SAML_SSO_LOGIN' }

  # TODO: Get rid of default scope
  # https://stackoverflow.com/a/1834250/939299
  default_scope { order(created_at: :desc) }
  scope :editable, -> { where(locked: false) }

  after_save :update_terms_history, if: -> { %w[TERMS_OF_SERVICE_CONTENT TERMS_OF_SERVICE_VERSION].include?(name) }
  after_commit :clear_cache

  def value
    serialized_value[:value]
  end

  def value=(value_to_assigned)
    self.serialized_value = {
      value: value_to_assigned
    }.with_indifferent_access
  end

  private

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
  def update_terms_history
    # Avoid infinite recursion when saving TERMS_OF_SERVICE_HISTORY
    content_config = InstallationConfig.find_by(name: 'TERMS_OF_SERVICE_CONTENT')
    version_config = InstallationConfig.find_by(name: 'TERMS_OF_SERVICE_VERSION')

    return if content_config.blank? || version_config.blank?

    version = version_config.value.to_s
    content = content_config.value.to_s

    # Find or initialize history config
    history_config = InstallationConfig.find_or_initialize_by(name: 'TERMS_OF_SERVICE_HISTORY')
    if history_config.new_record?
      history_config.locked = true
      history_config.value = {}.to_json
    end

    history = begin
      JSON.parse(history_config.value.to_s)
    rescue StandardError
      {}
    end
    history = {} unless history.is_a?(Hash)

    return unless history[version].nil? || history[version]['content'] != content

    history[version] = {
      'content' => content,
      'updated_at' => Time.current.iso8601
    }
    history_config.value = history.to_json
    history_config.save!
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity

  def set_lock
    self.locked = true if locked.nil?
  end

  def clear_cache
    GlobalConfig.clear_cache
  end

  def saml_sso_users_check
    return unless value == false || value == 'false'
    return unless User.exists?(provider: 'saml')

    errors.add(:base, 'Cannot disable SAML SSO login while users are using SAML authentication')
  end
end
