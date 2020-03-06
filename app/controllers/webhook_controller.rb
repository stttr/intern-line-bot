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
          p messages
          client.reply_message(event['replyToken'], messages)

        when Line::Bot::Event::MessageType::Image, Line::Bot::Event::MessageType::Video
          response = client.get_message_content(event.message['id'])
          tf = Tempfile.open("content")
          tf.write(response.body)
        end
      end
    }
    head :ok
  end

  def generate_messages(genre)
    case genre
    when "人気"
      popular_search_option = generate_search_option()
      data = access_tmdb_api(popular_search_option)
      movie_poster_path = data["results"].map { |movie| movie["poster_path"]}
      generate_carousel_messages(movie_poster_path)
    when "最新"

    else
      genre_id = TmdbGenre.find_id_by_name(genre)
      if genre_id.nil?
        not_found_genres_message()
      else
        found_genres_message(genre, genre_id)
      end
    end
  end

  def generate_search_option(**add_option)
    if add_option.nil?
      default_search_option()
    else
      default_search_option().merge(**add_option)
    end
  end

  def default_search_option
    {
      "api_key"=>ENV["TMDB_API_KEY"],
      "language"=>"ja",
      # "sort_by"=>"popularity.desc",
      "include_adult"=>"false",
      "include_video"=>"false",
      "page"=>"1",
    }
  end

  def access_tmdb_api(search_option)
    uri = URI(TmdbGenre.url)
    uri.query = URI.encode_www_form(search_option)
    res = Net::HTTP.get_response(uri)
    JSON.parse(res.body.to_s)
  end

  def generate_carousel_messages(movie_poster_path, columns_num=5)
    columns = []
    movie_poster_path.slice(0, columns_num).each { |img_name|
      p TmdbGenre.url_img()+img_name

      # columns.push({
      #     "imageUrl": TmdbGenre.url_img()+img_name,
      #     "action": {
      #        "type":"message",
      #        "label":img_name.slice(0,4),
      #        "text":img_name.slice(0,4)
      #     }
      # })

      columns.push(
        {
          "thumbnailImageUrl": TmdbGenre.url_img()+img_name,
          "imageBackgroundColor": "#000000",
          "title": "this is menu",
          "text": "description",
          "defaultAction": {
              "type": "uri",
              "label": "View detail",
              "uri": "http://example.com/page/123"
          },
          "actions": [
              {
                  "type": "uri",
                  "label": "View detail",
                  "uri": "http://example.com/page/111"
              }
          ]
        }
      )
    }

    # {
    #   "type": "template",
    #   "altText": "this is a image carousel template",
    #   "template": {
    #       "type": "image_carousel",
    #       "columns": columns
    #   }
    # }


    # {
    #   "thumbnailImageUrl": "https://example.com/bot/images/item1.jpg",
    #   "imageBackgroundColor": "#FFFFFF",
    #   "title": "this is menu",
    #   "text": "description",
    #   "defaultAction": {
    #       "type": "uri",
    #       "label": "View detail",
    #       "uri": "http://example.com/page/123"
    #   },
    #   "actions": [
    #       {
    #           "type": "postback",
    #           "label": "Buy",
    #           "data": "action=buy&itemid=111"
    #       },
    #       {
    #           "type": "postback",
    #           "label": "Add to cart",
    #           "data": "action=add&itemid=111"
    #       },
    #       {
    #           "type": "uri",
    #           "label": "View detail",
    #           "uri": "http://example.com/page/111"
    #       }
    #   ]
    # }



  {
    "type": "template",
    "altText": "this is a carousel template",
    "template": {
        "type": "carousel",
        "columns":columns,
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
    require 'pp'
    pp data["results"][0]["id"]
    data["results"].map { |movie| movie["title"] }.join("\n")
  end

  def not_found_genres_list_message()
    "こちらがジャンルリストです\n\n" + TmdbGenre.genres_list().join("\n")
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
