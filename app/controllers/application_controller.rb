class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  # protect_from_forgery with: :exception
  before_filter :permit_params
  # before_filter :login_if_not, :except => [:connect_google, :oauth2_callback_google, :youtube_liked, :send_to_telegram]
  before_filter :allow_iframe_requests

  def allow_iframe_requests
    response.headers.delete('X-Frame-Options')
  end

  def drive
    @query = params["query"] || ""
    render "welcome/drive"
  end

  def create_event
    current_user.schedule(params[:summary], params[:start], params[:end])
    render json: {message: "ok"}, status: 200
  end

  def agenda
    render "welcome/agenda"
  end

  def permit_params
    params.permit!
  end

  def attach
    # raise params.inspect
    file_id = params["file_id"]
    file_name = params["file_name"]
    mime = params["mime"]
    # file = current_user.get_drive_instance.get_file(file_id)
    # current_user.download(file_id, file_name)
    url = root_url+"download?file_name=#{file_name}&file_id=#{file_id}"
    attachments = {"src":  url.gsub("[","%5B").gsub("]","%5D").gsub(" ", "%20"), "mime": mime , "filename": file_name, "size": Random.new.rand(3 *1000*1000) }
    redirect_to params["redirect_to"]
  end

  def download
    file_id = params["file_id"]
    file_name = params["file_name"]
    current_user.download(file_id, file_name)
    url = root_url + file_name
    url = url.gsub("[","%5B").gsub("]","%5D").gsub(" ", "%20")
    send_file "public/#{file_name}", :x_sendfile=>true
  end

  def current_user
    User.find session[:current_user_id] if session[:current_user_id]
  end

  
  def login_if_not
    if !user_signed_in?
      session[:redirect_to] = request.path
      redirect_to "/connect/google"
    end
  end


  def connect_google
    credentials = User.initialize_google_credentials
    if !session[:fuck]
      current_user = User.create(email: "#{Random.rand(1000)}@easyfield.com", password: "User1234")
      puts sign_in(:user, current_user)
      session[:fuck] = current_user.id
      current_user.create_token_store

      credentials = current_user.get_credentials
      authorizer = current_user.get_authorizer
      url = authorizer.get_authorization_url(base_url: root_url)
      puts "Open the following URL in your browser and authorize the application."
      puts url
      puts "Enter the authorization code:"
      @google_consent_url = url
      redirect_to @google_consent_url   
    else
      current_user = User.find(session[:fuck])
      if current_user.crawl_status.blank?
        current_user.delay.get_docs
      end
      gon.watch.crawl_status = current_user.crawl_status
      if !params[:gon_return_variable].present?
        respond_to do |format|
          format.html {render "welcome/index"}
        end
      end
    end
    # redirect_to credentials.authorization_uri.to_s
  end

  def oauth2_callback_google
    current_user = User.find(session[:fuck])
    authorizer = current_user.get_authorizer
    credentials = authorizer.get_and_store_credentials_from_code(user_id: "", code: params["code"], base_url: "http://localhost:3000/callback/google/")
    gmail_add = current_user.get_gmail_instance.get_user_profile("me").email_address
    current_user.update_attributes(gmail_address: gmail_add, email: gmail_add)
    user = User.find_by(gmail_address: gmail_add)
    if user
      user.token_store.destroy
      user.token_store = current_user.token_store
      user.save
      session[:fuck] = user.id
    end
    redirect_to root_url
    # credentials = User.initialize_google_credentials
    # credentials.code = params["code"]
    # credentials.fetch_access_token!
    # user = User.save_from_google_user(credentials)
    # sign_in(:user, user)
    # if session[:redirect_to]
    #   redirect_to session[:redirect_to]
    # else
    #   redirect_to root_url
    # end
  end


  # def extract_details
  #   current_user = User.find(session[:fuck])
  #   if current_user.crawl_status.blank?
  #     current_user.crawl_docs
  #   end
  #   gon.watch.crawl_status = current_user.crawl_status
  # end

  def send_to_telegram
    title = params[:title]
    content = params[:content]
    link = params[:link]
    RestClient.post("https://api.telegram.org/bot287297665:AAGf5sJQeRa_l8-JGre-GkwTtaXV-3IDGH4/sendMessage", {"chat_id": 230551077, "text": "*#{title}*\n#{content} [link](#{link})", parse_mode: "Markdown", disable_web_page_preview: true})
    head :ok
  end

  def file
    params.permit!
    file_name = params["name"]
    send_file("#{Rails.root}/tmp/#{file_name}")
  end

  def index
  end
end
