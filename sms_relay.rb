#!/usr/bin/env ruby
#
# Copyright (C) 2014  Denver Gingerich <denver@ossguy.com>
#
# This file is part of Sopranica.
#
# Sopranica is free software: you can redistribute it and/or modify it under the
# terms of the GNU Affero General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option) any
# later version.
#
# Sopranica is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with Sopranica.  If not, see <http://www.gnu.org/licenses/>.

require 'blather/client/dsl'
require 'ffi-rzmq'
require 'json'

load 'settings-sms_relay.rb'	# has LOGIN_USER, LOGIN_PWD, and DESTINATION_JID

module SMSRelay
	extend Blather::DSL

	def self.log(msg)
		t = Time.now
		puts "LOG %d.%09d: %s" % [t.to_i, t.nsec, msg]
	end

	def self.log_raw(msg)
		puts msg
	end

	def self.normalize(number)
		if number.start_with?('011') then
			return number[3..-1]	# TODO: stylistically, '-1' ugly
		else
			return '1' + number
		end
	end

	def self.run
		@context = ZMQ::Context.new

		@pusher = @context.socket(ZMQ::PUSH)
		@pusher.bind('ipc://spr-mapper000-receiver')

		EM.run { client.run }
	end

	def self.zmq_terminate
		@pusher.close
		@context.terminate
	end

	setup LOGIN_USER, LOGIN_PWD

	when_ready { log 'ready to send messages; TODO - block send until now' }

	message :chat?, :body do |m|
		user_forward = normalize m.to.node
		user_device = normalize m.from.node

		zmq_message = {
			'message_type'	=> 'from_user',
			'user_forward'	=> user_forward,
			'user_device'	=> user_device,
			'body'		=> m.body
		}
		@pusher.send_string(JSON.dump zmq_message)

		log 'iMSG - ' + user_device + ' -> ' + user_forward + ': ' \
			+ m.body
	end

	message do |m|
		log "<<< received message stanza ==>"
		log_raw m.inspect
		log "<== end of message stanza"
	end

	presence do |p|
		log "<<< received presence stanza ==>"
		log_raw p.inspect
		log "<== end of presence stanza"
	end

	iq do |i|
		log "<<< received iq stanza ==>"
		log_raw i.inspect
		log "<== end of iq stanza"
	end

	pubsub do |s|
		log "<<< received pubsub stanza ==>"
		log_raw s.inspect
		log "<== end of pubsub stanza"
	end
end

SMSRelay.log 'starting Sopranica SMS Relay v0.02'

trap(:INT) {
	SMSRelay.log 'application terminating at user INT request'
	# TODO: add lock? so don't close socket while in middle of processing
	SMSRelay.zmq_terminate
	EM.stop
	exit
}
# TODO: add TERM handler?

Thread.new { SMSRelay.run }

count = 0
tmp = gets
while tmp == "\n" do
	msg = Blather::Stanza::Message.new(DESTINATION_JID, 'TesT' + count.to_s)
	SMSRelay.log '>>> sending message ==>'
	SMSRelay.log_raw msg.inspect
	SMSRelay.log '<== end of message to send'

	SMSRelay.log 'oMSG - ' + SMSRelay.jid.node + ' -> ' + msg.to.node \
		+ ': ' + msg.body
	SMSRelay.write_to_stream msg
	SMSRelay.log 'oMSG [sent]'

	count += 1
	tmp = gets
end

SMSRelay.log 'application terminating at user request'