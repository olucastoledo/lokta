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

  def accept_terms
    terms_version = params[:terms_version].presence || ensure_config_exists('TERMS_OF_SERVICE_VERSION', '1.0')

    @user.custom_attributes ||= {}
    @user.custom_attributes['accepted_terms_version'] = terms_version.to_s
    @user.custom_attributes['accepted_terms_at'] = Time.current
    @user.save!

    render json: { success: true }
  end

  def dismiss_announcement
    announcement_version = params[:announcement_version].presence || ensure_config_exists('CUSTOM_ANNOUNCEMENT_VERSION', '1.0')

    @user.custom_attributes ||= {}
    @user.custom_attributes['dismissed_announcement_version'] = announcement_version.to_s
    @user.custom_attributes['dismissed_announcement_at'] = Time.current
    @user.save!

    render json: { success: true }
  end

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
