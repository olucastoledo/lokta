# rubocop:disable Metrics/ClassLength
class Api::V1::ProfilesController < Api::BaseController
  before_action :set_user

  def show; end

  def update
    if password_params[:password].present?
      render_could_not_create_error('Invalid current password') and return unless @user.valid_password?(password_params[:current_password])

      @user.update!(password_params.except(:current_password))
    end

    @user.assign_attributes(profile_params)
    @user.custom_attributes.merge!(custom_attributes_params)
    @user.save!
  end

  def avatar
    @user.avatar.attachment.destroy! if @user.avatar.attached?
    @user.reload
  end

  def auto_offline
    @user.account_users.find_by!(account_id: auto_offline_params[:account_id]).update!(auto_offline: auto_offline_params[:auto_offline] || false)
  end

  def availability
    @user.account_users.find_by!(account_id: availability_params[:account_id]).update!(availability: availability_params[:availability])
  end

  def set_active_account
    @user.account_users.find_by(account_id: profile_params[:account_id]).update(active_at: Time.now.utc)
    head :ok
  end

  def resend_confirmation
    @user.send_confirmation_instructions unless @user.confirmed?
    head :ok
  end

  def reset_access_token
    @user.access_token.regenerate_token
    @user.reload
  end

  # rubocop:disable Metrics/MethodLength
  def terms_and_announcements
    terms_content = ensure_config_exists('TERMS_OF_SERVICE_CONTENT', '<p>Adicione os seus Termos de Serviço no Painel de Admin.</p>')
    terms_version = ensure_config_exists('TERMS_OF_SERVICE_VERSION', '1.0')

    announcement_active = ensure_config_exists('CUSTOM_ANNOUNCEMENT_ACTIVE', 'false') == 'true'
    announcement_content = ensure_config_exists('CUSTOM_ANNOUNCEMENT_CONTENT', '<p>Adicione o aviso/novidade no Painel de Admin.</p>')
    announcement_btn_text = ensure_config_exists('CUSTOM_ANNOUNCEMENT_BUTTON_TEXT', 'Clique Aqui')
    announcement_btn_link = ensure_config_exists('CUSTOM_ANNOUNCEMENT_BUTTON_LINK', 'https://')
    announcement_version = ensure_config_exists('CUSTOM_ANNOUNCEMENT_VERSION', '1.0')

    user_accepted_version = @user.custom_attributes['accepted_terms_version']
    accepted = user_accepted_version == terms_version

    user_dismissed_version = @user.custom_attributes['dismissed_announcement_version']
    dismissed = user_dismissed_version == announcement_version

    render json: {
      terms_of_service: {
        content: terms_content,
        version: terms_version,
        accepted: accepted
      },
      custom_announcement: {
        active: announcement_active,
        content: announcement_content,
        button_text: announcement_btn_text,
        button_link: announcement_btn_link,
        version: announcement_version,
        dismissed: dismissed
      }
    }
  end
  # rubocop:enable Metrics/MethodLength

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def accept_terms
    terms_version = params[:terms_version].presence || ensure_config_exists('TERMS_OF_SERVICE_VERSION', '1.0')

    @user.custom_attributes ||= {}
    @user.custom_attributes['accepted_terms_version'] = terms_version.to_s
    @user.custom_attributes['accepted_terms_at'] = Time.current.iso8601

    log_str = @user.custom_attributes['accepted_terms_log']
    log = begin
      JSON.parse(log_str.to_s)
    rescue StandardError
      []
    end
    log = [] unless log.is_a?(Array)

    unless log.any? { |item| item['version'] == terms_version.to_s }
      log << {
        'version' => terms_version.to_s,
        'accepted_at' => Time.current.iso8601
      }
      @user.custom_attributes['accepted_terms_log'] = log.to_json
    end

    @user.save!

    render json: { success: true }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  def dismiss_announcement
    announcement_version = params[:announcement_version].presence || ensure_config_exists('CUSTOM_ANNOUNCEMENT_VERSION', '1.0')

    @user.custom_attributes ||= {}
    @user.custom_attributes['dismissed_announcement_version'] = announcement_version.to_s
    @user.custom_attributes['dismissed_announcement_at'] = Time.current
    @user.save!

    render json: { success: true }
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def terms_acceptance_logs
    history_config = InstallationConfig.find_by(name: 'TERMS_OF_SERVICE_HISTORY')
    history = begin
      JSON.parse(history_config&.value.to_s)
    rescue StandardError
      {}
    end
    history = {} unless history.is_a?(Hash)

    user_log = @user.custom_attributes['accepted_terms_log']
    user_accepted_logs = begin
      JSON.parse(user_log.to_s)
    rescue StandardError
      []
    end
    user_accepted_logs = [] unless user_accepted_logs.is_a?(Array)

    if user_accepted_logs.empty? && @user.custom_attributes['accepted_terms_version'].present?
      user_accepted_logs << {
        'version' => @user.custom_attributes['accepted_terms_version'].to_s,
        'accepted_at' => @user.custom_attributes['accepted_terms_at'] || @user.updated_at.iso8601
      }
    end

    all_users_logs = []
    if @user.administrator?
      current_account = @user.active_account_user&.account
      if current_account.present?
        current_account.users.find_each do |u|
          u_log = u.custom_attributes['accepted_terms_log']
          u_accepted_logs = begin
            JSON.parse(u_log.to_s)
          rescue StandardError
            []
          end
          u_accepted_logs = [] unless u_accepted_logs.is_a?(Array)

          if u_accepted_logs.empty? && u.custom_attributes['accepted_terms_version'].present?
            u_accepted_logs << {
              'version' => u.custom_attributes['accepted_terms_version'].to_s,
              'accepted_at' => u.custom_attributes['accepted_terms_at'] || u.updated_at.iso8601
            }
          end

          u_accepted_logs.each do |entry|
            all_users_logs << {
              user_name: u.name,
              user_email: u.email,
              version: entry['version'],
              accepted_at: entry['accepted_at']
            }
          end
        end
      end
    end

    render json: {
      history: history,
      user_logs: user_accepted_logs,
      all_users_logs: all_users_logs
    }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  private

  def ensure_config_exists(name, default_value)
    config = InstallationConfig.find_by(name: name)
    return config.value if config.present?

    # Create it (locked: false so it's editable in the super admin panel)
    new_config = InstallationConfig.create!(
      name: name,
      value: default_value,
      locked: false
    )
    new_config.value
  end

  def set_user
    @user = current_user
  end

  def availability_params
    params.require(:profile).permit(:account_id, :availability)
  end

  def auto_offline_params
    params.require(:profile).permit(:account_id, :auto_offline)
  end

  def profile_params
    params.require(:profile).permit(
      :email,
      :name,
      :display_name,
      :avatar,
      :message_signature,
      :account_id,
      ui_settings: {}
    )
  end

  def custom_attributes_params
    params.require(:profile).permit(:phone_number)
  end

  def password_params
    params.require(:profile).permit(
      :current_password,
      :password,
      :password_confirmation
    )
  end
end
# rubocop:enable Metrics/ClassLength
