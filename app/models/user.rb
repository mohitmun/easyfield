# require 'google/apis/oauth2_v2/representations.rb'
# require 'google/apis/oauth2_v2/service.rb'
# require 'google/apis/oauth2_v2/classes.rb'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'fileutils'
require 'google/apis/calendar_v3'
require 'google/apis/gmail_v1'
require 'rmail'
class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable

  after_initialize :init
  has_one :token_store
  
  store_accessor :content, :last_message

  def init
    self.content ||= {}
    # self.content.deep_symbolize_keys!
    # @session = get_gdrive_session
  end


  Gmail = Google::Apis::GmailV1
  Drive = Google::Apis::DriveV3
  
  def file_list(query)
    drive = get_drive_instance
    page_token = nil
    limit = 1000
    begin
      result = drive.list_files(q: query,
                                page_size: [limit, 100].min,
                                page_token: page_token,
                                fields: 'files(id,name),next_page_token')

      result.files.each { |file| puts "#{file.id}, #{file.name}" }
      limit -= result.files.length
      if result.next_page_token
        page_token = result.next_page_token
      else
        page_token = nil
      end
    end while !page_token.nil? && limit > 0
  end

  def get_drive_instance
    drive = Drive::DriveService.new
    drive.authorization = get_credentials
    return drive
  end

  def get_gmail_instance
    gmail = Gmail::GmailService.new
    gmail.authorization = get_credentials
    return gmail
  end

  def get_calender_instance
    calendar = Calendar::CalendarService.new
    calendar.authorization = get_credentials
    return calendar
  end

  def schedule(summary, start, _end)
    calendar = get_calender_instance
    event = {
      summary: summary,
      start: {
        date_time: Time.parse(start).iso8601
      },
      end: {
        date_time: Time.parse(_end).iso8601
      }
    }

    event = calendar.insert_event('primary', event, send_notifications: true)
  end

  def todays_agenda
    calendar = get_calender_instance
    page_token = nil
    limit = 1000
    now = Time.now
    max = now + 24.hours
    now = now.iso8601
    max = max.iso8601
    results = []
    begin
      result = calendar.list_events('primary', max_results: [limit, 100].min, single_events: true, order_by: 'startTime', time_min: now, time_max: max, page_token: page_token, fields: 'items(id,summary,start),next_page_token')
      result.items.each do |event|
        results << event
        time = event.start.date_time || event.start.date
        puts "#{time}, #{event.summary}"
      end
      limit -= result.items.length
      if result.next_page_token
        page_token = result.next_page_token
      else
        page_token = nil
      end
    end while !page_token.nil? && limit > 0
    return results
  end


  def get_credentials
    local_url = "http://localhost:3000"
    authorizer = get_authorizer
    credentials = authorizer.get_credentials("") rescue nil
    return credentials
  end
  Calendar = Google::Apis::CalendarV3
  def download(file_id, file)
      drive = get_drive_instance
      path = "public/#{file}"
      file = File.open(path, 'wb')
      file.binmode
      dest = file
      drive.get_file(file_id, download_dest: dest)

      if dest.is_a?(StringIO)
        dest.rewind
        STDOUT.write(dest.read)
      else
        puts "File downloaded to #{file}"
      end
      return file
    end

  def get_authorizer
    client_id = Google::Auth::ClientId.new(CLI_ID, CLI_SEC)
    # token_store = Google::Auth::Stores::FileTokenStore.new(:file => "lol")
    authorizer = Google::Auth::UserAuthorizer.new(client_id, [Drive::AUTH_DRIVE, Gmail::AUTH_SCOPE, "https://www.google.com/calendar/feeds"], token_store)
  end

  def send_mail(to, subject, body)
    gmail = get_gmail_instance
    message = RMail::Message.new
    message.header['To'] = to
    message.header['Subject'] = subject
    message.body = body
    gmail.send_user_message('me', upload_source: StringIO.new(message.to_s), content_type: 'message/rfc822')
  end
  HISTORY_IDS = []

  def get_history(history_id, root_url)
    gmail = get_gmail_instance
    histories = gmail.list_user_histories("me", start_history_id: history_id).history || []
    histories.each do |history|
      if history.messages
        HISTORY_IDS.delete(history.id)
        history.messages.each do |added_message|
          message = gmail.get_user_message("me", added_message.id)
          text = ""
          last_message = {}
          selected_headers = message.payload.headers.select{|a| ["Subject", "From"].include?(a.name)}
          selected_headers.each do |header|
            text = text + header.name + " : " + header.value + "\n"
            last_message[header.name.downcase] = header.value
            puts "===="*50
            puts last_message
            puts "===="*50
          end
          if message.payload.body.data
            text = text + "Body : " + message.payload.body.data.strip
          end
          puts "===="*50
          puts last_message
          puts "===="*50
          self.last_message = last_message
          self.save
          send_to_bot_mail(last_message["from"], last_message["subject"], text, root_url)
        end
      else
      end
    end
    if histories.count == 0
      HISTORY_IDS << history_id
      sleep 7
      get_history(HISTORY_IDS.sort[-1], root_url)
    end
  end

  CLI_ID = "877172711738-u5k37fpfios222i09vdk00e6aq1t58m7.apps.googleusercontent.com"
  CLI_SEC = "4uxNP6kRtOWBWbo30nhi6_2w"
  def self.initialize_google_credentials
    credentials = Google::Auth::UserRefreshCredentials.new(
    client_id: CLI_ID,
    client_secret: CLI_SEC,

    scope: [
          "https://www.googleapis.com/auth/userinfo.email",
          "https://www.googleapis.com/auth/userinfo.profile",
         "https://www.googleapis.com/auth/drive",
         "https://mail.google.com/",
         # "https://www.google.com/calendar/feeds"
         "https://www.googleapis.com/auth/calendar"
       ],
    redirect_uri: "http://localhost:3000/oauth2/callback/google/")
  end

  # def self.save_from_google_user(credentials)
  #   authservice = Google::Apis::Oauth2V2::Oauth2Service.new
  #   authservice.authorization = credentials
  #   userinfo = authservice.get_userinfo_v2(fields: "email")
  #   user = User.find_by(email: userinfo.email)
  #   if user
  #     user.content[:google][:access_token] = credentials.access_token
  #     user.save
  #   else
  #     user = User.create(email: userinfo.email, password: SecureRandom.hex, content: {google: {access_token: credentials.access_token}})
  #   end
  #   return user
  # end
end
