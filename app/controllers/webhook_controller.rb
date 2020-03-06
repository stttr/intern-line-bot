require 'line/bot'
require 'net/http'
require 'json'

class WebhookController < ApplicationController
  protect_from_forgery except: [:callback] # CSRF対策無効化

  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  def callback
    body = request.body.read

    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
      head 470
    end

    events = client.parse_events_from(body)
    events.each { |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          messages = generate_messages(event.message['text'])
          res = client.reply_message(event['replyToken'], messages)
          p res
          p res.body
        end
      end
    }
    head :ok
  end

  def generate_messages(genre)
    case genre
    when "ジャンル"
      generate_genre_button_message()
    else
      search_option = generate_search_option(select_search_option_by_genre(genre))
      if search_option.has_key?("with_genres")
        data = access_tmdb_api(search_option)
        generate_carousel_messages(data)
      else
        found_genres_search_message()
      end
    end
  end

  def select_search_option_by_genre(genre)
    case genre
    when "人気"
      {}
    when "最新"
      now_time = Time.now
      {
        "sort_by"=>"release_date.desc",
        "release_date.lte"=>[
            now_time.year.to_s,
            now_time.month.to_s.rjust(2, "0"),
            now_time.day.to_s.rjust(2, "0")
        ].join("-")
      }
    else
      genre_id = TmdbApi.find_id_by_name(genre)
      {
        "with_genres"=>genre_id
      }
    end
  end

  def generate_search_option(add_option)
    if add_option.blank?
      default_search_option()
    else
      default_search_option().merge(add_option)
    end
  end

  def default_search_option
    {
      "api_key"=>ENV["TMDB_API_KEY"],
      "language"=>"ja",
      "sort_by"=>"popularity.desc",
      "include_adult"=>"false",
      "include_video"=>"false",
      "page"=>"1",
    }
  end

  def access_tmdb_api(search_option)
    uri = URI(TmdbApi.url)
    uri.query = URI.encode_www_form(search_option)
    res = Net::HTTP.get_response(uri)
    JSON.parse(res.body.to_s)
  end

  def generate_carousel_messages(data, columns_num=10)
    columns = []
    data["results"].slice(0, columns_num).each { |movie|
      if not movie["poster_path"].blank?
        columns.push(
          {
            "thumbnailImageUrl": TmdbApi.url_img()+movie["poster_path"],
            "imageBackgroundColor": "#000000",
            "title": movie["title"].truncate(60),
            "text": movie["original_title"],
            "actions": [
              {
                "type": "uri",
                "label": "Search this movie",
                "uri": TmdbApi.url_movie+"/"+movie["id"].to_s+"?language=ja"
              }
            ]
          }
        )
      end
    }

    {
      "type": "template",
      "altText": "映画一覧です。",
      "template": {
          "type": "carousel",
          "columns": columns,
          "imageAspectRatio": "rectangle",
          "imageSize": "contain"
      }
    }
  end

  def generate_genre_button_message(columns_num=10)
    columns = []
    TmdbApi.genres_list().sample(columns_num).each { |genre|
      columns.push(
        {
          "text": genre,
          "actions":[
            {
              "type":"message",
              "label": genre,
              "text": genre
            }
          ]
        }
      )
    }

    {
      "type": "template",
      "altText": "映画ジャンル一覧です。",
      "template": {
          "type": "carousel",
          "columns": columns,
          "imageAspectRatio": "rectangle",
          "imageSize": "contain"
      }
    }
  end




  def not_found_genres_message
    messages = []
    messages.push({
      type: 'text',
      text: not_found_genres_pre_message()
    })
    messages.push({
      type: 'text',
      text: not_found_genres_search_message()
    })
    messages.push({
      type: 'text',
      text: not_found_genres_list_message()
    })
    messages
  end

  def not_found_genres_pre_message
    <<~EOS
    そのジャンルはありませんでした...
    代わりに全ジャンルから探します！\n
    EOS
  end

  def not_found_genres_search_message
    option = generate_search_option()
    data = access_tmdb_api(option)
    data["results"].map { |movie| movie["title"] }.join("\n")
  end

  def not_found_genres_list_message()
    "こちらがジャンルリストです\n\n" + TmdbApi.genres_list().join("\n")
  end

  def found_genres_message(genre, genre_id)
    messages = []
    messages.push({
      type: 'text',
      text: found_genres_pre_message(genre)
    })
    messages.push({
      type: 'text',
      text: found_genres_search_message(genre_id)
    })
  end

  def found_genres_pre_message(genre)
    <<~EOS
    #{genre}のおすすめはこちらです！\n
    EOS
  end

  def found_genres_search_message(genre_id)
    option = generate_search_option({"with_genres" => genre_id})
    data = access_tmdb_api(option)

    data["results"].map { |movie| movie["title"] }.join("\n")
  end
end
