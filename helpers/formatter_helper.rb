# encoding: utf-8

module Sinatra
  module Bionomia
    module Helper
      module FormatterHelper

        include ActionView::Helpers::NumberHelper

        Date::DATE_FORMATS[:month_and_year] = '%B, %Y'
        Date::DATE_FORMATS[:year] = '%Y'

        def h(text)
          Rack::Utils.escape_html(text)
        end

        def url_for url_fragment, mode=:path_only
          case mode
          when :path_only
            base = request.script_name
          when :full_url
            if (request.scheme == 'http' && request.port == 80 ||
                request.scheme == 'https' && request.port == 443)
              port = ""
            else
              port = ":#{request.port}"
            end
            base = "#{request.scheme}://#{request.host}#{port}#{request.script_name}"
          else
            raise "Unknown script_url mode #{mode}"
          end
          "#{base}#{url_fragment}"
        end

        def link_to link_text, url, mode=:path_only
          if(url_for(url,mode)[0,2] == "!!")
            trimmed_url = url_for(url,mode)[2..-1]
            "<a href=\"#{trimmed_url}\">#{link_text}</a>"
          else
            "<a href=\"#{url_for(url,mode)}\">#{link_text}</a>"
          end
        end

        def checked_tag(user_action, action)
          (user_action == action) ? "checked" : ""
        end

        def active_class(user_action, action)
          (user_action == action) ? "active" : ""
        end

        def radio_checked(user_action, action)
          (user_action == action) ? true : false
        end

        def country_name(code)
          I18nData.countries(I18n.locale)[code] rescue nil
        end

        def profile_image(user, size=nil)
          img = Settings.base_url + "/images/photo.png"
          cloud_img = "https://abekpgaoen.cloudimg.io/height/200/x/"
          if size == "thumbnail"
            cloud_img = "https://abekpgaoen.cloudimg.io/crop/24x24/n/"
          elsif size == "thumbnail_grey"
            cloud_img = "https://abekpgaoen.cloudimg.io/crop/24x24/fgrey/"
          elsif size == "medium"
            cloud_img = "https://abekpgaoen.cloudimg.io/crop/48x48/n/"
          elsif size == "social"
            cloud_img = "https://abekpgaoen.cloudimg.io/crop/240x240/n/"
          end
          if user.image_url
            if user.wikidata
              img =  cloud_img + user.image_url
            else
              img = cloud_img + Settings.base_url + "/images/users/" + user.image_url
            end
          end
          img
        end

        def organization_image(organization, size=nil)
          img = nil
          cloud_img = "https://abekpgaoen.cloudimg.io/height/200/x/"
          if size == "thumbnail"
            cloud_img = "https://abekpgaoen.cloudimg.io/crop/24x24/n/"
          elsif size == "medium"
            cloud_img = "https://abekpgaoen.cloudimg.io/crop/48x48/n/"
          elsif size == "social"
            cloud_img = "https://abekpgaoen.cloudimg.io/crop/240x240/n/"
          end
          if organization.image_url
            img = cloud_img + organization.image_url
          end
          img
        end

        def signature_image(user)
          img = Settings.base_url + "/images/signature.png"
          cloud_img = "https://abekpgaoen.cloudimg.io/height/80/x/"
          if user.signature_url
            img =  cloud_img + user.signature_url
          end
          img
        end

        def format_agent(n)
          { id: n[:_source][:id],
            score: n[:_score],
            name: [n[:_source][:family].presence, n[:_source][:given].presence].compact.join(", ")
          }
        end

        def format_agents
          @results.map{ |n|
            { id: n[:_source][:id],
              score: n[:_score],
              fullname: n[:_source][:fullname],
              fullname_reverse: [n[:_source][:family].presence, n[:_source][:given].presence].compact.join(", ")
            }
          }
        end

        def format_users
          @results.map{ |n|
            lifespan = n[:_source][:wikidata] ? format_lifespan(n[:_source]) : nil
            { id: n[:_source][:id],
              score: n[:_score],
              orcid: n[:_source][:orcid],
              wikidata: n[:_source][:wikidata],
              fullname: n[:_source][:fullname],
              fullname_reverse: n[:_source][:fullname_reverse],
              thumbnail: n[:_source][:thumbnail],
              lifespan: lifespan,
              description: n[:_source][:description]
            }
          }
        end

        def format_organizations
          @results.map{ |n|
            { id: n[:_source][:id],
              score: n[:_score],
              name: n[:_source][:name],
              address: n[:_source][:address],
              institution_codes: n[:_source][:institution_codes],
              isni: n[:_source][:isni],
              ringgold: n[:_source][:ringgold],
              grid: n[:_source][:grid],
              wikidata: n[:_source][:wikidata],
              preferred: n[:_source][:preferred]
            }
          }
        end

        def format_datasets
          @results.map{ |n|
            { id: n[:_source][:id],
              score: n[:_score],
              title: n[:_source][:title].truncate(100, separator: ' '),
              datasetkey: n[:_source][:datasetkey],
              top_institution_codes: n[:_source][:top_institution_codes]
            }
          }
        end

        def format_taxon
          @results.map{ |n|
            { id: n[:_source][:id],
              name: n[:_source][:name]
            }
          }
        end

        def format_articles
          @results.map{ |n|
            { id: n[:_source][:id],
              score: n[:_score],
              citation: n[:_source][:citation],
              doi: n[:_source][:doi]
            }
          }
        end

        def format_lifespan(user)
          if user.is_a?(User)
            date_born = user[:date_born]
            date_died = user[:date_died]
          else
            date_born = Date.parse(user[:date_born]) rescue nil
            date_died = Date.parse(user[:date_died]) rescue nil
          end
          if user[:date_born_precision] == "day"
            born = I18n.l date_born, format: :long
          elsif user[:date_born_precision] == "month"
            born = I18n.l date_born, format: :month_and_year
          elsif user[:date_born_precision] == "year"
            born = I18n.l date_born, format: :year
          else
            born = "?"
          end

          if user[:date_died_precision] == "day"
            died = I18n.l date_died, format: :long
          elsif user[:date_died_precision] == "month"
            died = I18n.l date_died, format: :month_and_year
          elsif user[:date_died_precision] == "year"
            died = I18n.l date_died, format: :year
          else
            died = "?"
          end

          ["&#42; " + born, died + " &dagger;"].join(" &ndash; ")
        end

        def sort_icon(field, direction)
          sorted_field = params[:order]
          if field == sorted_field
            if direction == "asc"
              "<i class=\"fas fa-sort-down\"></i>"
            elsif direction == "desc"
              "<i class=\"fas fa-sort-up\"></i>"
            end
          else
            "<i class=\"fas fa-sort\"></i>"
          end
        end

      end
    end
  end
end
