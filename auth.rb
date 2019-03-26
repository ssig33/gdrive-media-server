SCOPES = [
  'https://www.googleapis.com/auth/userinfo.email',
  'https://www.googleapis.com/auth/drive'
].join(' ')


helpers do
  def redirect_uri
    if ENV['RACK_ENV'] == 'development'
      uri = URI.parse(request.url)
      uri.path = '/auth/google_oauth2/callback'
      uri.query = nil
      uri.to_s
    else
      "https://#{ENV['DOMAIN']}/auth/google_oauth2/callback"
    end
  end

  def auth
    unless session[:credentials]
      session[:to] =  request.query_string != "" ? "#{request.path}?#{request.query_string}" : request.path
      redirect '/auth'
    else
      refresh
    end
  end

  def refresh
    client_opts = JSON.parse(session[:credentials])
    auth_client = Signet::OAuth2::Client.new(client_opts)
    auth_client.refresh!
    session[:credentials] = auth_client.to_json
  end

  def get_auth_client
    $client_secrets ||= Google::APIClient::ClientSecrets.load
    $client_secrets.to_authorization
  end
end

get '/auth' do
  auth_client = get_auth_client
  auth_client.update!(
    scope: 'https://www.googleapis.com/auth/drive https://www.googleapis.com/auth/userinfo.email',
    redirect_uri: redirect_uri,
    additional_parameters: {
      approval_prompt: "force"
    }
  )
  redirect auth_client.authorization_uri.to_s
end

get '/auth/google_oauth2/callback' do
  auth_client = get_auth_client
  auth_client.update!(
    scope: 'https://www.googleapis.com/auth/drive',
    redirect_uri: redirect_uri
  )
  auth_client.code = request['code']
  auth_client.fetch_access_token!
  
  session[:credentials] = auth_client.to_json

  if session[:to]
    redirect session[:to]
  else
    redirect '/home'
  end
end
