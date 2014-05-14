#!/usr/bin/env ruby
# encoding: utf-8

require 'sinatra'
require 'sinatra/activerecord'
require 'sinatra/reloader' if development?
require 'slim'
require 'logger'

# Add out application's lib dir to the require LOAD_PATH
lib_path = File.expand_path('lib', File.dirname(__FILE__))
$LOAD_PATH.unshift lib_path unless $LOAD_PATH.include? lib_path

db_path = {
  production:  "sqlite3:#{ENV['OPENSHIFT_DATA_DIR']}db.sqlite3",
  development: 'sqlite3:tmp/dev.sqlite3',
  test:        'sqlite3:tmp/test.sqlite3'
}
set :database, db_path[settings.environment]

# Logger
$logger = Logger.new("#{ENV['OPENSHIFT_LOG_DIR']}app.log", 2, 1_024_000)

# Mailings model
class Mailing < ActiveRecord::Base
  validates_uniqueness_of :order_ref
  validates_presence_of :order_ref, :date_sent
  validates_inclusion_of :is_post, in: [true, false]
end

get '/' do
  "The time at the server is #{Time.now.strftime '%l:%M %P'}."
end

# Deliveries.
# Through which clients track their deliveries.

require 'dpd_reports.rb'

Thread.new do
  loop do
    DpdReports.new.fetch_reports.save_to_db
    Mailing.delete_all(['date_sent < ?', Time.now - 7_776_000]) # 90 days
    sleep 10_800 # 3 hours
  end
end

# The page with this form is located in public/deliveries.html
post '/deliveries' do
  @dpd_url = 'http://www.dpd.co.uk/apps/tracking/?reference='
  @mailing = Mailing.find_by(order_ref: params[:order_ref])
  slim :deliveries
end
