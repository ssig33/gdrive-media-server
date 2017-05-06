require 'bundler'
Bundler.require 
require 'google/apis/drive_v2'
require 'google/api_client/client_secrets'
require 'digest/md5'

REDIS = ENV['REDIS_URL'] ? Redis.new(url: ENV['REDIS_URL']) : Redis.new

if development?
  require 'sinatra/reloader'
end

use Rack::Session::Cookie, :secret => 'ohmysecret!!'

helpers do
  def query_builder q
    q.gsub("'", ' ').split(" ").map{|x|
      "(fullText contains '#{x}')"
    }.join(" and ")
  end

  def  embed link
    link += "&autoplay=1"
  end

  def files query: "", page_token: ""
    page_token = page_token.to_s
    query = query.to_s
    
    client_opts = JSON.parse(session[:credentials])
    auth_client = Signet::OAuth2::Client.new(client_opts)
    drive = Google::Apis::DriveV2::DriveService.new
    opts = {order_by: "createdDate desc", options: { authorization: auth_client }}
    unless query == ''
      opts[:q] =  query_builder(query)
    end
    unless page_token == ''
      opts[:page_token] = page_token
    end
    files = drive.list_files(opts)
    
    return files.to_h[:items].select{|x| x[:embed_link] }.select{|x| x[:original_filename]}, files.next_page_token
  end

  def next_page
    request.path + "?" + [request.query_string, "page_token=#{@next_page_token}"].join("&")
  end
end


get '/' do
  if session[:credentials] 
    redirect "/home"
  end
  haml :top
end

def redis_key str
  Digest::MD5.hexdigest(str)
end

get '/home' do
  auth
  @files, @next_page_token = files(query: params[:query], page_token: params[:page_token])
  haml :files
end

post '/api/status' do
  auth
  ary = JSON.parse(request.body.read)
  keys = ary.map{|x| redis_key("#{x}/watched/#{session[:email]}") }
  r = REDIS.mget(*keys)
  result = []
  ary.each_with_index{|id,i|
    result << {id: id, watched: !!r[i]}
  }
  result.to_json
end

post '/api/watch' do
  auth
  key = request.body.read.chomp
  content_type :json
  REDIS.set(redis_key("#{key}/watched/#{session[:email]}"), "alloy")
  "true"
end

require './auth'
