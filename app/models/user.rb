# require 'google/apis/oauth2_v2/representations.rb'
# require 'google/apis/oauth2_v2/service.rb'
# require 'google/apis/oauth2_v2/classes.rb'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'fileutils'
require 'google/apis/calendar_v3'
require 'google/apis/people_v1'
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
  CRAWL_STATUS = ""
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


  def people
    peopleService =  Google::Apis::PeopleV1::PeopleService.new
    peopleService.authorization = get_credentials
    return peopleService
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

  def get_list_proofs
    list_of_proofs = []
  end

  def get_personal_info
    return {:birthday=>{:day=>16, :month=>12, :year=>1992}, :dob=>"16/12/1992", :gender=>"male", :photo=>"https://lh3.googleusercontent.com/-Rlsptw9SvzQ/AAAAAAAAAAI/AAAAAAAABKA/nZfXuUmIJBI/photo.jpg", :first_name=>"mohit", :last_name=>"munjani"}
    person = people.get_person("people/me")
    return {birthday:{day: person.birthdays.last.date.day, month: person.birthdays.last.date.month, year: person.birthdays.last.date.year },dob: "#{person.birthdays.last.date.day}/#{person.birthdays.last.date.month}/#{person.birthdays.last.date.year}", gender: person.genders.last.value, photo: person.photos.last.url, first_name: person.names.last.given_name, last_name: person.names.last.family_name}
  end

  def get_pan_card_preview
    return [{:name=>"IMG_20170128_110956324.jpg", :type=>"image/jpeg", :path=>"public/IMG_20170128_110956324.jpg"}]
    result = []
    file_list = get_drive_instance.list_files(q: "fullText contains 'permanent account number' and  mimeType contains 'image'")
    file_list.files.each do |file|
      result << {name: file.name, type: file.mime_type, path: download(file.id, file.name).path}
    end
    return result
  end



  def crawl_drive(fullText, mimeType='image')
    result = []
    file_list = get_drive_instance.list_files(q: "fullText contains '#{fullText}' and  mimeType contains '#{mimeType}'")
    file_list.files.each do |file|
      result << {id: file.id, name: file.name, type: file.mime_type, 
        # path: download(file.id, file.name).path, 
        message: ""}
    end
    return result
  end

  def crawl_gmail(q)
    result = []
    messages = get_gmail_instance.list_user_messages("me", q: "#{q} has:attachment -in:chats").messages
    messages.each do |message|
      message_object = get_gmail_instance.get_user_message("me", message.id)
      message_parts = message_object.payload.parts.select{|part| !part.body.attachment_id.blank?}
      message_parts.each do |message_part|
        att_res = get_gmail_instance.get_user_message_attachment("me", message.id, message_part.body.attachment_id)
        f = File.open("public/" + message_part.filename, "wb")
        f.write(att_res.data)
        f.close
        result << {id: message.id, name: message_part.filename, type: message_part.mime_type, path: message_part.filename, message: message_object.payload.headers.select{|abc| abc.name.downcase=="subject"}[0].value}
      end
    end
    return result
  end


  def get_form_16_preview
    return crawl_gmail("Certificate under Section 203")
  end

  def get_driving_licence_preview
    return [{:name=>"IMG_20170128_110956324.jpg", :type=>"image/jpeg", :path=>"public/IMG_20170128_110956324.jpg"}]
    result = []
    file_list = get_drive_instance.list_files(q: "fullText contains 'Driving licence' and  mimeType contains 'image'")
    file_list.files.each do |file|
      result << {name: file.name, type: file.mime_type, path: download(file.id, file.name).path}
    end
    return result
  # Driving licence
  end

  def get_voter_preview
    crawl_drive("election commision of india")
  end

  def get_passport_review
    crawl_drive("republic of india")
  end
  # Age proof:
  #   Pan Card
  #   Driving License
  #   Aadhar Card with Affidavit
  #   Passport
  # Income Proof
  #   Salary slip
  # Proof of residence
  #   Driving License
  #   Aadhar Card with Affidavit
  #   Passport
  # Identity Proof
  #   Driving License
  #   Aadhar Card with Affidavit
  #   Pan Card
  #   Passport
  #   Voter

  # u.get_drive_instance.list_files(q: "fullText contains 'mh01'")
  # u.get_gmail_instance.list_user_messages("me", q: "pan card has:attachment -in:chats filename:jpg")
  #u.get_gmail_instance.get_user_message("me", "1577f6dd83d57787")
  # u.get_gmail_instance.get_user_message_attachment("me", "1577f6dd83d57787","ANGjdJ92_VgevbHhFzOBo_OTYZ8JI1i_w_wOGsk3RRBp_ueUIp6WIgZEInYvhFiyWPi_lAMqjX_MVW8D8_rbDbBaR_yzFqMzKe8rsGiX1lgH_v5706efr3gxX7vjVwuJ-3LVPZ-B904aRjezmuv05fwKMciTvogIGgNuaCRFmOdy64HH2dCc99u3HEfuFmvduCdDhAXMUPbKcjAMq_0JQMP7MHBqBnvyunzAXpAe8jXMk5tXL6KSoKMqn2eACjU5_mqo_jvjeVYiQC5gEIii_NEQqegsOUxmbhoV_stRUGqsNf_55CwqIfRZjtSsLjc")
 # f = File.open("mama", "wb")f.write(att_res.data);puts "c"
  def save_attachment
    
  end

  def get_authorizer
    client_id = Google::Auth::ClientId.new(CLI_ID, CLI_SEC)
    # token_store = Google::Auth::Stores::FileTokenStore.new(:file => "lol")
    authorizer = Google::Auth::UserAuthorizer.new(client_id, [Drive::AUTH_DRIVE, Gmail::AUTH_SCOPE, "https://www.google.com/calendar/feeds", Google::Apis::PeopleV1::AUTH_USER_BIRTHDAY_READ, Google::Apis::PeopleV1::AUTH_USERINFO_PROFILE,Google::Apis::PeopleV1::AUTH_USER_ADDRESSES_READ,Google::Apis::PeopleV1::AUTH_USER_PHONENUMBERS_READ], token_store)
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
