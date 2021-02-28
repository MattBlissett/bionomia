# encoding: utf-8

module Bionomia
  class ExistingClaimsWorker
    include Sidekiq::Worker
    sidekiq_options queue: :existing_claims

    def perform(row)
      recs = row["gbifIDs_recordedByIDs"]
                .tr('[]', '')
                .split(',')
      ids = row["gbifIDs_identifiedByIDs"]
                .tr('[]', '')
                .split(',')

      uniq_recs = recs - ids
      uniq_ids = ids - recs
      both = recs & ids

      row["agentIDs"].split("|").each do |id|
        u = get_user(id.strip)
        next if u.nil? || User::BOT_IDS.include?(u.id)
        if !uniq_recs.empty?
          uo = uniq_recs.map{|r| [u.id, r.to_i, "recorded", User::GBIF_AGENT_ID]}
          import_user_occurrences(uo)
        end
        if !uniq_ids.empty?
          uo = uniq_ids.map{|r| [u.id, r.to_i, "identified", User::GBIF_AGENT_ID]}
          import_user_occurrences(uo)
        end
        if !both.empty?
          uo = both.map{|r| [u.id, r.to_i, "recorded,identified", User::GBIF_AGENT_ID]}
          import_user_occurrences(uo)
        end
        u.flush_caches
      end
    end

    def get_user(id)
      user = nil
      if id.wiki_from_url
        user = get_wiki_user(id.wiki_from_url) rescue nil
      end
      if id.orcid_from_url && id.orcid_from_url.is_orcid?
        user = get_orcid_user(id.orcid_from_url) rescue nil
      end
      if id.viaf_from_url
        w = ::Bionomia::WikidataSearch.new
        wikidata = w.wiki_by_property('viaf', id.viaf_from_url)[:wikidata] rescue nil
        if wikidata
          user = get_wiki_user(wikidata)
        end
      end
      if id.ipni_from_url
        w = ::Bionomia::WikidataSearch.new
        wikidata = w.wiki_by_property('ipni', id.ipni_from_url)[:wikidata] rescue nil
        if wikidata
          user = get_wiki_user(wikidata)
        end
      end
      if id.bhl_from_url
        w = ::Bionomia::WikidataSearch.new
        wikidata = w.wiki_by_property('bhl', id.bhl_from_url)[:wikidata] rescue nil
        if wikidata
          user = get_wiki_user(wikidata)
        end
      end
      if id.zoobank_from_url
        w = ::Bionomia::WikidataSearch.new
        wikidata = w.wiki_by_property('zoobank', id.zoobank_from_url)[:wikidata] rescue nil
        if wikidata
          user = get_wiki_user(wikidata)
        end
      end
      user
    end

    def get_orcid_user(id)
      destroyed = DestroyedUser.find_by_identifier(id)
      if !destroyed.nil? && !destroyed.redirect_to.nil?
        user = User.find_by_identifier(destroyed.redirect_to)
      else
        user = User.create_with({ orcid: id })
                   .find_or_create_by({ orcid: id })
      end
      user
    end

    def get_wiki_user(id)
      destroyed = DestroyedUser.find_by_identifier(id)
      if !destroyed.nil? && !destroyed.redirect_to.nil?
        user = User.find_by_identifier(destroyed.redirect_to)
      else
        user = User.create_with({ wikidata: id })
                   .find_or_create_by({ wikidata: id })
        if !user.valid_wikicontent?
          user.delete_search
          user.delete
          user = nil
        elsif user.valid_wikicontent? && !user.is_public?
          user.is_public = true
          user.made_public = Time.now
          user.save
        end
      end
      user
    end

    def import_user_occurrences(uo)
      UserOccurrence.transaction do
        UserOccurrence.import [:user_id, :occurrence_id, :action, :created_by], uo, batch_size: 5_000, validate: false, on_duplicate_key_ignore: true
      end
    end

  end
end
