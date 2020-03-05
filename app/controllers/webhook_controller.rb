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
          uri = URI("https://api.themoviedb.org/3/discover/movie")
          genre_id = TmdbGenre.find_id_by_name(event.message['text'])

          messages = []
          if genre_id.nil? then
            pre_message = <<~EOS
            そのジャンルはありませんでした...
            代わりに全ジャンルから探します！\n

            EOS
          else
            pre_message = <<~EOS
            #{event.message['text']}のおすすめはこちらです！\n
            EOS
          end
          messages.push({
            type: 'text',
            text: pre_message
          })

          # TMDb api
          search_option = {
            "api_key"=>ENV["TMDB_API_KEY"],
            "language"=>"ja",
            "sort_by"=>"popularity.desc",
            "include_adult"=>"false",
            "include_video"=>"false",
            "page"=>"1",
          }
          if genre_id.nil? then
            search_option["with_genres"] = genre_id.to_s
          end
          uri.query = URI.encode_www_form(search_option)
          res = Net::HTTP.get_response(uri)
          puts res.code
          data = JSON.parse(res.body.to_s)

          recommend_movies = ""
          data["results"].each{ |movie|
            recommend_movies += movie["title"]+"\n"
          }
          messages.push({
            type: 'text',
            text: recommend_movies
          })

          genres_list_message = "こちらがジャンルリストです\n\n"
          if genre_id.nil? then
            TmdbGenre::GENRES.keys.each{ |genre_name|
              genres_list_message += "#{genre_name}\n"
            }
            messages.push({
              type: 'text',
              text: genres_list_message
            })
          end

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
end
