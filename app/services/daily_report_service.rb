class DailyReportService
  def initialize(account, date = nil)
    @account = account
    @date = date || yesterday_date
  end

  def perform
    webhook_url = @account.settings['daily_report_webhook_url'].presence || ENV.fetch('DAILY_REPORT_WEBHOOK_URL', nil)
    if webhook_url.blank?
      Rails.logger.warn "[DailyReportService] No webhook URL configured for account #{@account.id}"
      return false
    end

    report_payload = generate_payload
    send_webhook(webhook_url, report_payload)
  end

  def generate_report_text
    tz = ActiveSupport::TimeZone[timezone] || Time.zone
    start_time = tz.parse("#{@date} 00:00:00")
    end_time = tz.parse("#{@date} 23:59:59")

    # 1. General Metrics
    new_convs = @account.conversations.where(created_at: start_time..end_time)
    resolved_convs = @account.conversations.where(status: :resolved, updated_at: start_time..end_time)
    active_convs = @account.conversations.where(updated_at: start_time..end_time)
    open_convs_count = @account.conversations.where(status: :open).count

    # Channel Metrics
    @new_by_inbox = new_convs.group(:inbox_id).count
    @active_by_inbox = active_convs.group(:inbox_id).count
    inbox_ids = (@new_by_inbox.keys + @active_by_inbox.keys).uniq
    @inboxes = inbox_ids.any? ? @account.inboxes.where(id: inbox_ids).index_by(&:id) : {}

    # 2. General Labels
    general_labels = count_general_labels(active_convs)

    # 3. Agent Metrics
    agent_metrics = build_agent_metrics(new_convs, active_convs)

    # 4. Sales and Notes
    sales, total_sales_value = extract_sales(active_convs)

    # Build report sections
    report = []
    report << "📊 *Relatório Diário de Atendimentos - #{@account.name}*"
    suffix = if @date == yesterday_date
               ' (Ontem)'
             elsif @date == today_date
               ' (Hoje)'
             else
               ''
             end
    report << "📅 *Referente a:* #{format_date(@date)}#{suffix}"
    report << ''
    report << build_general_summary_text(new_convs.count, resolved_convs.count, active_convs.count, open_convs_count)
    report << build_channels_text(@new_by_inbox, @active_by_inbox, @inboxes) if @inboxes.any?
    report << build_labels_text(general_labels) if general_labels.any?
    report << build_agents_text(agent_metrics) if agent_metrics.any?
    report << build_sales_text(sales, total_sales_value) if sales.any?

    report.join("\n")
  end

  def generate_payload
    report_text = generate_report_text

    tz = ActiveSupport::TimeZone[timezone] || Time.zone
    start_time = tz.parse("#{@date} 00:00:00")
    end_time = tz.parse("#{@date} 23:59:59")

    new_convs_count = @account.conversations.where(created_at: start_time..end_time).count
    resolved_convs_count = @account.conversations.where(status: :resolved, updated_at: start_time..end_time).count
    active_convs_count = @account.conversations.where(updated_at: start_time..end_time).count
    open_convs_count = @account.conversations.where(status: :open).count

    recipient_phone = @account.settings['daily_report_whatsapp_number'].presence

    {
      account_id: @account.id,
      account_name: @account.name,
      date: @date,
      recipient_phone: recipient_phone,
      report: report_text,
      data: {
        total_new_conversations: new_convs_count,
        total_resolved_conversations: resolved_convs_count,
        total_active_conversations: active_convs_count,
        total_open_conversations: open_convs_count,
        channels: inboxes_payload
      }
    }
  end

  private

  def count_general_labels(active_convs)
    general_labels = Hash.new(0)
    active_convs.each do |conv|
      conv.cached_label_list_array.each { |label| general_labels[label] += 1 }
    end
    general_labels
  end

  def build_agent_metrics(new_convs, active_convs)
    agent_metrics = []
    @account.account_users.includes(:user).find_each do |au|
      agent = au.user
      agent_active = active_convs.where(assignee_id: agent.id)
      next if agent_active.count.zero?

      agent_resolved = active_convs.where(assignee_id: agent.id, status: :resolved).count
      agent_created = new_convs.where(assignee_id: agent.id).where.not(first_reply_created_at: nil)
      avg_frt = agent_created.average('EXTRACT(EPOCH FROM (first_reply_created_at - created_at))')&.to_f

      agent_labels = Hash.new(0)
      agent_active.each do |conv|
        conv.cached_label_list_array.each { |label| agent_labels[label] += 1 }
      end

      agent_metrics << {
        name: agent.name,
        handled_conversations: agent_active.count,
        resolved_conversations: agent_resolved,
        avg_first_response_time_seconds: avg_frt,
        labels: agent_labels
      }
    end
    agent_metrics
  end

  def extract_sales(active_convs)
    sales = []
    seen_contacts = Set.new
    total_sales_value = 0.0

    active_convs.each do |conv|
      contact = conv.contact
      next if contact.blank? || seen_contacts.include?(contact.id)

      valor_venda = contact.custom_attributes['valor_venda']
      next unless valor_venda.present? && (valor_venda.to_f.positive? || valor_venda.to_s.strip.present?)

      seen_contacts.add(contact.id)
      latest_note = contact.notes.order(created_at: :desc).first&.content

      sales << {
        contact_name: contact.name,
        valor_venda: valor_venda,
        stage: contact.custom_attributes['etapa_kanban'] || 'Aguardando...',
        latest_note: latest_note,
        conversation_id: conv.display_id
      }

      val = valor_venda.to_s.gsub(/[^0-9.,]/, '').tr(',', '.').to_f
      total_sales_value += val
    end

    [sales, total_sales_value]
  end

  def build_general_summary_text(new_count, resolved_count, active_count, open_count)
    summary_word = if date_context_word == 'Ontem'
                     'de Ontem'
                   elsif date_context_word == 'Hoje'
                     'de Hoje'
                   else
                     date_context_word
                   end

    [
      "📈 *Resumo Geral #{summary_word}:*",
      "• Novas conversas criadas: #{new_count}",
      "• Conversas resolvidas: #{resolved_count}",
      "• Conversas ativas (com mensagens/atualizações): #{active_count}",
      "• Total de conversas em aberto (atual): #{open_count}",
      ''
    ].join("\n")
  end

  def build_channels_text(new_by_inbox, active_by_inbox, inboxes)
    lines = ["🔌 *Conversas por Canal (#{date_context_word}):*"]
    inboxes.each do |inbox_id, inbox|
      new_count = new_by_inbox[inbox_id] || 0
      active_count = active_by_inbox[inbox_id] || 0
      lines << "• #{inbox.name}: #{new_count} novas, #{active_count} ativas"
    end
    lines << ''
    lines.join("\n")
  end

  def inboxes_payload
    return [] if @inboxes.blank?

    @inboxes.map do |inbox_id, inbox|
      {
        inbox_id: inbox.id,
        inbox_name: inbox.name,
        channel_type: inbox.channel_type,
        new_conversations: @new_by_inbox[inbox_id] || 0,
        active_conversations: @active_by_inbox[inbox_id] || 0
      }
    end
  end

  def build_labels_text(general_labels)
    lines = ["🏷️ *Conversas por Etiqueta (#{date_context_word}):*"]
    general_labels.sort_by { |_, v| -v }.each do |label, count|
      lines << "• #{label}: #{count}"
    end
    lines << ''
    lines.join("\n")
  end

  def build_agents_text(agent_metrics)
    lines = ["👥 *Desempenho dos Agentes (#{date_context_word}):*"]
    agent_metrics.each do |metrics|
      lines << "*#{metrics[:name]}*"
      lines << "  • Conversas atendidas: #{metrics[:handled_conversations]}"
      lines << "  • Resolvidas: #{metrics[:resolved_conversations]}"
      lines << "  • Tempo médio de 1ª resposta: #{format_duration(metrics[:avg_first_response_time_seconds])}"
      if metrics[:labels].any?
        labels_str = metrics[:labels].map { |k, v| "#{k} (#{v})" }.join(', ')
        lines << "  • Etiquetas: #{labels_str}"
      end
    end
    lines << ''
    lines.join("\n")
  end

  def build_sales_text(sales, total_sales_value)
    lines = [
      "💰 *Vendas Registradas (#{date_context_word}):*",
      "Total estimado: R$ #{format_currency(total_sales_value)}",
      ''
    ]
    frontend_url = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    sales.each do |sale|
      lines << "*Contato:* #{sale[:contact_name]} (#{sale[:stage]})"
      lines << "  • Valor: #{sale[:valor_venda]}"
      lines << "  • Última Anotação: \"#{sale[:latest_note].strip}\"" if sale[:latest_note].present?
      lines << "  • Conversa: #{frontend_url}/app/accounts/#{@account.id}/conversations/#{sale[:conversation_id]}"
    end
    lines << ''
    lines.join("\n")
  end

  def timezone
    @account.reporting_timezone.presence || 'America/Sao_Paulo'
  end

  def yesterday_date
    tz = ActiveSupport::TimeZone[timezone] || Time.zone
    tz.now.yesterday.strftime('%Y-%m-%d')
  end

  def today_date
    tz = ActiveSupport::TimeZone[timezone] || Time.zone
    tz.now.strftime('%Y-%m-%d')
  end

  def date_context_word
    if @date == yesterday_date
      'Ontem'
    elsif @date == today_date
      'Hoje'
    else
      "do dia #{format_date(@date)}"
    end
  end

  def format_date(date_str)
    Date.parse(date_str).strftime('%d/%m/%Y')
  rescue StandardError
    date_str
  end

  def format_currency(val)
    format('%.2f', val).tr('.', ',').gsub(/(\d)(?=(\d\d\d)+(?!\d))/, '\\1.')
  end

  def format_duration(seconds)
    return 'N/A' if seconds.blank? || seconds.to_f.nan?

    seconds = seconds.to_f
    if seconds < 60
      "#{seconds.round}s"
    elsif seconds < 3600
      "#{(seconds / 60).round}m"
    else
      hours = (seconds / 3600).floor
      minutes = ((seconds % 3600) / 60).round
      "#{hours}h #{minutes}m"
    end
  end

  def send_webhook(url, payload)
    response = HTTParty.post(
      url,
      body: payload.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: 10
    )

    Rails.logger.error "[DailyReportService] Failed to send webhook to #{url}. Status: #{response.code}" unless response.success?

    response.success?
  rescue StandardError => e
    Rails.logger.error "[DailyReportService] Error posting daily report webhook: #{e.message}"
    false
  end
end
