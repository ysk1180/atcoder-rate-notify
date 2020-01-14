require 'net/http'
require 'json'
require 'aws-record'
require 'slack-notifier'

USER_IDS = ['toyon', 'katoken', 'ysk1180', 'lastgleam', 'yoitengineer', 'morix1500']

class AtcoderRate
  include Aws::Record
  string_attr :user_id, hash_key: true
  integer_attr :rate
end

def fetch_data(user_id)
  url = URI.parse("https://us-central1-atcoderusersapi.cloudfunctions.net/api/info/username/#{user_id}")
  https = Net::HTTP.new(url.host, url.port)
  https.use_ssl = true
  req = Net::HTTP::Get.new(url.path)
  res = https.request(req)
  hash = JSON.parse(res.body)
  [hash['data']['rating'], hash['data']['user_color']]
end

def rates
  rates = []
  USER_IDS.each do |user_id|
    atcoder_rate = AtcoderRate.find(user_id: user_id) || AtcoderRate.new
    last_rate = atcoder_rate.rate
    rate, color = fetch_data(user_id)
    difference = last_rate ? rate - last_rate : '-'
    difference = '±0' if difference == 0
    atcoder_rate.user_id = user_id
    atcoder_rate.rate = rate
    atcoder_rate.save
    rates.push({user_id: user_id, rate: rate, difference: difference, color: color})
  end
  rates
end

def slack_notify(sorted_rates)
  message = ""
  sorted_rates.each.with_index(1) do |hash, index|
    message.concat("#{index}位: #{hash[:user_id]} #{hash[:rate]}(#{hash[:difference]}) :#{hash[:color]}:\n")
  end
  message.chomp
  notifier = Slack::Notifier.new ENV['WEBHOOK_URL'] do
    defaults channel: '#atcoder', link_names: 1
  end
  notifier.post text: message
end

def lambda_handler(event:, context:)
  sorted_rates = rates.sort_by{ |hash| hash[:rate] }.reverse
  slack_notify(sorted_rates)
  { statusCode: 200, body: sorted_rates }
end
