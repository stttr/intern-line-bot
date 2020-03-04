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
      # event is Message from LINE
      when Line::Bot::Event::Message
        case event.type
        # when message is Text
        when Line::Bot::Event::MessageType::Text
          # return my message
          # api url
          tmdb_url_discover_movie = "https://api.themoviedb.org/3/discover/movie"
          uri = URI(tmdb_url_discover_movie)

          # genre search
          genre = TmdbGenre.find_id_by_name(event.message['text'])

          # get query, serch option
          qer = {
            "api_key"=>ENV["TMDB_API_KEY"],
            "language"=>"ja",
            "sort_by"=>"popularity.desc",
            "include_adult"=>"false",
            "include_video"=>"false",
            "page"=>"1",
          }

          # return messages
          messages = []

          # serch genres define
          if genre.nil? then
            pre_message = <<-EOS
そのジャンルはありませんでした...
代わりに全ジャンルから探します！

            EOS
          else
            pre_message = <<-EOS
#{event.message['text']}のおすすめはこちらです！

            EOS
            qer["with_genres"] = genre.to_s
          end

          # add pre message
          messages.push({
            type: 'text',
            text: pre_message
          })

          #define uri
          uri.query = URI.encode_www_form(qer)

          # get response
          res = Net::HTTP.get_response(uri)

          # print status code
          puts res.code

          # transform json data to hash
          data = JSON.parse(res.body.to_s)

          # add message recommend movies
          recommend_movies = ""
          data["results"].each{ |movie|
            recommend_movies += movie["title"]+"\n"
          }

          messages.push({
            type: 'text',
            text: recommend_movies
          })

          # add message genres_list
          genres_list = "こちらがジャンルリストです\n\n"
          if genre.nil? then
            TmdbGenre::GENRES.keys.each{ |genre|
              genres_list += "#{genre}\n"
            }

            messages.push({
              type: 'text',
              text: genres_list
            })
          end

          # reply for LINE
          client.reply_message(event['replyToken'], messages)

        # when message is Image or Message
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
