class Dataset < ActiveRecord::Base
  has_many :occurrences, primary_key: :datasetKey, foreign_key: :datasetKey

  validates :datasetKey, presence: true

  before_update :set_update_time
  after_create :add_search
  after_update :update_search, :fix_occurrences_count
  after_destroy :remove_search

  def has_claim?
    UserOccurrence.from("user_occurrences FORCE INDEX (user_occurrence_idx)")
                  .joins(:occurrence)
                  .where(occurrences: { datasetKey: datasetKey })
                  .where(visible: true)
                  .limit(1).exists?
  end

  alias_method :has_user?, :has_claim?

  def has_agent?
    determiner = OccurrenceDeterminer
                    .select(:agent_id)
                    .joins(:occurrence)
                    .where(occurrences: { datasetKey: datasetKey }).limit(1)
    recorder = OccurrenceRecorder
                    .select(:agent_id)
                    .joins(:occurrence)
                    .where(occurrences: { datasetKey: datasetKey }).limit(1)
    determiner.exists? || recorder.exists?
  end

  def users
    subq = UserOccurrence.select(:user_id, :visible)
                         .from("user_occurrences FORCE INDEX (user_occurrence_idx)")
                         .joins(:occurrence)
                         .where(occurrences: { datasetKey: datasetKey })
                         .distinct
    User.joins("INNER JOIN (#{subq.to_sql}) a ON a.user_id = users.id")
        .where("a.visible": true)
  end

  def user_ids
    users.select(:id)
  end

  def user_occurrences
    UserOccurrence.joins(:user)
                  .joins(:claimant)
                  .joins(:occurrence)
                  .where(occurrences: { datasetKey: datasetKey })
  end

  def claimed_occurrences
    UserOccurrence.select(:id, :visible, "occurrences.*")
                  .joins(:occurrence)
                  .where(occurrences: { datasetKey: datasetKey })
  end

  def claimed_occurrences_count
    UserOccurrence.select(:occurrence_id)
                  .from("user_occurrences FORCE INDEX (user_occurrence_idx)")
                  .joins(:occurrence)
                  .where(occurrences: { datasetKey: datasetKey })
                  .where(user_occurrences: { visible: true })
                  .count
  end

  def agents
    determiners = OccurrenceDeterminer
                    .select(:agent_id)
                    .joins(:occurrence)
                    .where(occurrences: { datasetKey: datasetKey })
    recorders = OccurrenceRecorder
                    .select(:agent_id)
                    .joins(:occurrence)
                    .where(occurrences: { datasetKey: datasetKey })
    combined = recorders
                    .union_all(determiners)
                    .unscope(:order)
                    .select(:agent_id)
                    .distinct
    Agent.where(id: combined).order(:family)
  end

  def agents_occurrence_counts
    determiners = OccurrenceDeterminer
                    .joins(:occurrence)
                    .where(occurrences: { datasetKey: datasetKey })
    recorders = OccurrenceRecorder
                    .joins(:occurrence)
                    .where(occurrences: { datasetKey: datasetKey })
    recorders.union(determiners)
             .joins(:agent)
             .group(:agent_id)
             .order(Arel.sql("count(*) desc"))
             .count
  end

  def agents_occurrence_count
    determiners = OccurrenceDeterminer
                    .select(:agent_id)
                    .joins(:occurrence)
                    .where(occurrences: { datasetKey: datasetKey })
                    .distinct
    recorders = OccurrenceRecorder
                    .select(:agent_id)
                    .joins(:occurrence)
                    .where(occurrences: { datasetKey: datasetKey })
                    .distinct
    recorders.union_all(determiners)
             .unscope(:order)
             .select(:agent_id)
             .distinct
             .count
  end

  def agents_occurrence_unclaimed_counts
    determiners = OccurrenceDeterminer
                    .joins(:occurrence)
                    .left_outer_joins(occurrence: :user_occurrences)
                    .where(occurrences: { datasetKey: datasetKey })
                    .where(user_occurrences: { occurrence_id: nil })
                    .distinct
    recorders = OccurrenceRecorder
                    .joins(:occurrence)
                    .left_outer_joins(occurrence: :user_occurrences)
                    .where(occurrences: { datasetKey: datasetKey })
                    .where(user_occurrences: { occurrence_id: nil })
                    .distinct
    recorders.union(determiners)
             .group(:agent_id)
             .order(Arel.sql("count(*) desc"))
             .count
  end

  def scribes
    subq = UserOccurrence.select(:created_by, :visible)
                         .from("user_occurrences FORCE INDEX (user_occurrence_idx)")
                         .joins(:occurrence)
                         .where(occurrences: { datasetKey: datasetKey })
                         .where.not(created_by: User::BOT_IDS)
                         .where("user_occurrences.user_id != user_occurrences.created_by")
                         .distinct
    User.joins("INNER JOIN (#{subq.to_sql}) a ON a.created_by = users.id")
        .where("a.visible": true)
  end

  def license_icon(form = "button")
    return if license.nil?
    size = (form == "button") ? "88x31" : "80x15"
    if license.include?("/zero/")
      url = "https://i.creativecommons.org/p/zero/1.0/#{size}.png"
    elsif license.include?("/by/")
      url = "https://i.creativecommons.org/l/by/4.0/#{size}.png"
    elsif license.include?("/by-nc/")
      url = "https://i.creativecommons.org/l/by-nc/4.0/#{size}.png"
    else
      url = "/images/Clear1x1.gif"
    end
    url
  end

  def institution_codes
    occurrences.pluck(:institutionCode).compact.uniq.sort
  end

  def top_institution_codes
    codes = occurrences.pluck(:institutionCode)
               .inject(Hash.new(0)) { |total, e| total[e] += 1 ;total}
    if codes.size < 5 && codes.values.sum > 10_000
        codes.sort_by{|k,v| v}
             .reverse
             .first(4)
             .to_h
             .keys rescue []
    else
      []
    end
  end

  def collected_before_birth_after_death
    UserOccurrence.joins(:occurrence)
                  .joins(:user)
                  .where(occurrences: { datasetKey: datasetKey })
                  .where(action: ["recorded", "recorded,identified", "identified,recorded"])
                  .where("users.date_born >= occurrences.eventDate_processed OR users.date_died =< occurrences.eventDate_processed")
  end

  def current_occurrences_count
    begin
      response = RestClient::Request.execute(
        method: :get,
        url: "https://api.gbif.org/v1/occurrence/search?dataset_key=#{datasetKey}&limit=0"
      )
      response = JSON.parse(response, :symbolize_names => true)
      response[:count].to_i
    rescue
      0
    end
  end

  def timeline_recorded(start_year: 1000, end_year: Time.now.year)
    start_date = Date.new(start_year, 1, 1)
    end_date = Date.new(end_year, 12, 31)

    subq = UserOccurrence.from("user_occurrences FORCE INDEX (user_occurrence_idx)")
                         .select(:user_id, :eventDate_processed, :visible)
                         .joins(:occurrence)
                         .where(user_occurrences: { action: ['recorded', 'identified,recorded', 'recorded,identified'] })
                         .where(occurrences: { datasetKey: datasetKey})
                         .where("eventDate_processed BETWEEN ? AND ?", start_date, end_date)
                         .distinct

    User.select("users.*", "MIN(a.eventDate_processed) AS min_date", "MAX(a.eventDate_processed) AS max_date")
        .joins("INNER JOIN (#{subq.to_sql}) a ON a.user_id = users.id")
        .where("a.visible": true)
        .where.not("a.eventDate_processed": nil)
        .group(:id)
        .order("min_date")
  end

  def timeline_identified(start_year: 1000, end_year: Time.now.year)
    start_date = Date.new(start_year, 1, 1)
    end_date = Date.new(end_year, 12, 31)

    subq = UserOccurrence.from("user_occurrences FORCE INDEX (user_occurrence_idx)")
                         .select(:user_id, :dateIdentified_processed, :visible)
                         .joins(:occurrence)
                         .where(user_occurrences: { action: ['identified', 'identified,recorded', 'recorded,identified'] })
                         .where(occurrences: { datasetKey: datasetKey})
                         .where("dateIdentified_processed BETWEEN ? AND ?", start_date, end_date)
                         .distinct

    User.select("users.*", "MIN(a.dateIdentified_processed) AS min_date", "MAX(a.dateIdentified_processed) AS max_date")
        .joins("INNER JOIN (#{subq.to_sql}) a ON a.user_id = users.id")
        .where("a.visible": true)
        .where.not("a.dateIdentified_processed": nil)
        .group(:id)
        .order("min_date")
  end

  def article_occurrences
    ArticleOccurrence.select(:id, :article_id, :occurrence_id)
                     .joins(:occurrence)
                     .joins(:user_occurrences)
                     .where(occurrences: { datasetKey: datasetKey })
                     .where(user_occurrences: { visible: true })
                     .distinct
  end

  private

  def set_update_time
    self.updated_at = Time.now
  end

  def add_search
    es = Bionomia::ElasticDataset.new
    if !es.get(self)
      es.add(self)
    end
  end

  def update_search
    es = Bionomia::ElasticDataset.new
    es.update(self)
  end

  def remove_search
    es = Bionomia::ElasticDataset.new
    begin
      es.delete(self)
    rescue
    end
  end

  def fix_occurrences_count
    Occurrence.counter_culture_fix_counts only: :dataset, where: { datasetKey: datasetKey }
  end

end
