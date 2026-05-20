class Api::V2::Accounts::WeeklySummariesController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def index
    since_time = parse_time(params[:since], 7.days.ago.beginning_of_day)
    until_time = parse_time(params[:until], Time.current)

    convs = fetch_conversations(since_time, until_time)
    csat = fetch_csat_responses(since_time, until_time)

    render json: build_response_hash(since_time, until_time, convs, csat)
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  def parse_time(time_str, default)
    return default if time_str.blank?

    Time.zone.parse(time_str)
  rescue ArgumentError, TypeError
    default
  end

  def fetch_conversations(since_time, until_time)
    base_scope = Current.account.conversations
    if params[:inbox_id].present?
      inbox_ids = Array(params[:inbox_id]).map(&:to_i)
      base_scope = base_scope.where(inbox_id: inbox_ids)
    end
    {
      base: base_scope,
      created: base_scope.where(created_at: since_time..until_time),
      resolved: base_scope.where(status: :resolved, updated_at: since_time..until_time),
      open: base_scope.where(status: :open)
    }
  end

  def fetch_csat_responses(since_time, until_time)
    csat = CsatSurveyResponse.where(account_id: Current.account.id, created_at: since_time..until_time)
    if params[:inbox_id].present?
      inbox_ids = Array(params[:inbox_id]).map(&:to_i)
      csat = csat.filter_by_inbox_id(inbox_ids)
    end
    csat
  end

  def build_response_hash(since_time, until_time, convs, csat)
    sample_size = (params[:sample_size].presence || 10).to_i
    {
      period: { since: since_time, until: until_time },
      metrics: general_metrics(convs[:created], convs[:resolved], convs[:open], csat),
      agent_metrics: build_agent_metrics(convs[:created], convs[:resolved]),
      unattended_conversations: unattended_conversations(convs[:base]),
      unhappy_conversations: unhappy_conversations(csat),
      sample_conversations: sample_conversations(convs[:resolved], sample_size)
    }
  end

  def general_metrics(created, resolved, open, csat)
    convs_with_reply = created.where.not(first_reply_created_at: nil)
    avg_frt = convs_with_reply.average('EXTRACT(EPOCH FROM (first_reply_created_at - created_at))')&.to_f
    avg_rt = resolved.average('EXTRACT(EPOCH FROM (updated_at - created_at))')&.to_f

    {
      total_new_conversations: created.count,
      total_resolved_conversations: resolved.count,
      total_open_conversations: open.count,
      avg_first_response_time_seconds: avg_frt&.round(2),
      avg_resolution_time_seconds: avg_rt&.round(2),
      csat: {
        average_rating: csat.average(:rating)&.to_f&.round(2),
        total_responses: csat.count
      }
    }
  end

  def build_agent_metrics(created, resolved)
    Current.account.account_users.includes(:user).filter_map do |au|
      build_single_agent_stats(au.user, created, resolved)
    end
  end

  def build_single_agent_stats(user, created, resolved)
    assigned_count = created.where(assignee_id: user.id).count
    resolved_count = resolved.where(assignee_id: user.id).count
    return nil if assigned_count.zero? && resolved_count.zero?

    avg_frt = created.where(assignee_id: user.id).where.not(first_reply_created_at: nil)
                     .average('EXTRACT(EPOCH FROM (first_reply_created_at - created_at))')&.to_f
    avg_rt = resolved.where(assignee_id: user.id)
                     .average('EXTRACT(EPOCH FROM (updated_at - created_at))')&.to_f

    {
      agent_id: user.id,
      name: user.name,
      email: user.email,
      assigned_conversations: assigned_count,
      resolved_conversations: resolved_count,
      avg_first_response_time_seconds: avg_frt&.round(2),
      avg_resolution_time_seconds: avg_rt&.round(2)
    }
  end

  def unattended_conversations(base_scope)
    unattended = base_scope.where(status: [:open, :pending]).where.not(waiting_since: nil).order(waiting_since: :asc).limit(20)
    unattended.map do |c|
      last_msg = c.last_incoming_message
      {
        conversation_id: c.display_id,
        contact_name: c.contact.name,
        waiting_since: c.waiting_since,
        waiting_duration_seconds: (Time.current - c.waiting_since).to_i,
        last_message: last_msg&.content_for_llm || last_msg&.content
      }
    end
  end

  def unhappy_conversations(csat)
    unhappy_csat = csat.where(rating: 1..2).order(created_at: :desc).limit(10)
    unhappy_csat.map do |r|
      conv = r.conversation
      {
        conversation_id: conv.display_id,
        agent_name: conv.assignee&.name || 'N/A',
        contact_name: conv.contact.name,
        rating: r.rating,
        feedback_message: r.feedback_message || r.csat_review_notes,
        transcript: conv.to_llm_text(token_limit: 2000)
      }
    end
  end

  def sample_conversations(resolved, sample_size)
    sample_convs = resolved.order('RANDOM()').limit(sample_size)
    sample_convs.map do |c|
      {
        conversation_id: c.display_id,
        agent_name: c.assignee&.name || 'N/A',
        contact_name: c.contact.name,
        transcript: c.to_llm_text(token_limit: 2000)
      }
    end
  end
end
