#!/usr/bin/env ruby
# encoding: utf-8

require 'csv'
require 'net/ftp'

# Pulls the CSV for each delivery from the DPD FTP, parses, and adds to the db
# Reports that have been read are moved to a subdir
class DpdReports
  attr_reader :reports

  def initialize
    @site, @login, @pass, @reports =
      ENV['ftp_dpd_site'], ENV['ftp_dpd_login'], ENV['ftp_dpd_pass'], []
  end

  # Fetches the DPD report files from the FTP specified by the ftp_dpd_site,
  # ftp_dpd_login, and ftp_dpd_pass enviroment variables.
  #
  # The reports are moved to the 'parsed_reports' dir within the ftp after
  # being read.
  def fetch_reports
    return self unless @site && @login && @pass
    Net::FTP.open(@site, @login, @pass) do |ftp|
      ftp.passive = true # No bind- openshift doesn't allow it
      tmp_dir = ENV['OPENSHIFT_TMP_DIR']
      files = ftp.nlst
      ftp.mkdir 'parsed_reports' unless files.include? 'parsed_reports'
      files.select { |e| e.match(/\.OUT$/) }.each do |file|
        ftp.gettextfile(file, tmp_dir + file)
        @reports << parse_report(
          File.read(tmp_dir + file).force_encoding('BINARY')
        ).merge(date_sent: ftp.mtime(file))
        ftp.rename(file, "parsed_reports/#{file}")
        File.delete tmp_dir + file # if production?
      end
    end
    $logger.info { "#{@reports.size} reports read from dpd_ftp" }
    self
  end

  # Saves the reports to the database. Nothing will happen unless the
  # {#fetch_reports} method is called beforehand.
  #
  # @return [Array] The return values from each Mailing.create
  def save_to_db
    @reports.map do |report|
      $logger.info do
        Mailing.create report
      end
    end
  end

  private

  def parse_report(report)
    report = CSV.parse_line(report)
    {
      order_ref: report[1].force_encoding('UTF-8'),
      is_post:   false,
      dpd_ref:   report[11].force_encoding('UTF-8')
    }
  end
end
