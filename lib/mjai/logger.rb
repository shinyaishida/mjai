# frozen_string_literal: true

require 'logger'

module Mjai
  LOGGER = Logger.new($stdout)
  LOGGER.level = Logger::DEBUG
  LOGGER.formatter = proc do |severity, datetime, _progname, msg|
    format("[%<date>s %<pid>d] %5<severity>s -- %<msg>s\n", {
             date: datetime.strftime('%Y-%m-%d %H:%M:%S'),
             pid: Process.pid,
             severity: severity,
             msg: msg
           })
  end
end
