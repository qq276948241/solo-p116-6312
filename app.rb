require 'bundler/setup'
require 'sinatra/base'
require 'sinatra/json'
require 'json'

ENV['SINATRA_ENV'] ||= 'development'

require_relative 'config/database'
require_relative 'models/init'

class Bookstore < Sinatra::Base
  set :bind, '0.0.0.0'
  set :port, 4567
  set :show_exceptions, true
  set :raise_errors, false

  configure do
    use Rack::CommonLogger
  end

  before do
    content_type :json, charset: 'utf-8'
  end

  error do |e|
    status 500
    {
      code: 500,
      message: "服务器错误: #{e.message}",
      data: nil
    }.to_json
  end

  error Sequel::ValidationFailed do |e|
    status 422
    {
      code: 422,
      message: e.message,
      data: nil
    }.to_json
  end

  error JSON::ParserError do |e|
    status 400
    {
      code: 400,
      message: '请求体格式错误',
      data: nil
    }.to_json
  end

  get '/' do
    {
      code: 0,
      message: '欢迎使用社区旧书店后台管理API',
      data: {
        name: 'Bookstore API',
        version: '1.0.0',
        endpoints: {
          books: '/api/books',
          members: '/api/members',
          orders: '/api/orders'
        }
      }
    }.to_json
  end

  get '/health' do
    begin
      DB.run 'SELECT 1'
      db_status = 'ok'
    rescue => e
      db_status = "error: #{e.message}"
    end

    {
      code: 0,
      message: 'success',
      data: {
        status: 'running',
        environment: ENV['SINATRA_ENV'],
        database: db_status,
        timestamp: Time.now.to_s
      }
    }.to_json
  end
end

require_relative 'routes/books'
require_relative 'routes/members'
require_relative 'routes/orders'

Bookstore.run! if __FILE__ == $0
