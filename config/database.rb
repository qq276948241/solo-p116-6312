ENV['SINATRA_ENV'] ||= 'development'

require 'sequel'
require 'sqlite3'

DB = Sequel.sqlite("db/bookstore_#{ENV['SINATRA_ENV']}.db")

Sequel::Model.plugin :timestamps, update_on_create: true
