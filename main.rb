require 'net/http'
require 'json'

class PredictItAnalyzer
  def initialize
  end

  def fetch_data
    uri = URI('https://www.predictit.org/api/marketdata/all')
    http_result = Net::HTTP.get(uri)

    @market_data = JSON.parse(http_result)
    @results = []
    @should_play_alert = false
  end

  def run
    fetch_data
    calculate_results
    sort_results('guaranteed_profit')
    print_results
    play_alert
    sleep(50+rand(20))
    run
  end

  def print_results
    @results.each do |result|
      puts ''
      puts ''
      result.each do |k, v|
        puts "#{k}: #{v}"
      end
    end
  end

  def sort_results(sort_field='guaranteed_profit')
    @results.sort! do |a, b|
      a[sort_field] <=> b[sort_field]
    end
  end

  def calculate_results
    @market_data['markets'].each do |market|
      result_details = {}
      result_details['name'] = market['name']
      result_details['id'] = market['id']

      guaranteed_profit = calculate_guaranteed_profit(market)
      next unless guaranteed_profit

      result_details['current_buy_no_prices'] = buy_no_prices(market).compact.map {|p| (p * 100).round }
      # result_details['current_sell_no_prices'] = sell_no_prices(market).compact.map {|p| (p * 100).round }
      # result_details['sell_shares_advantage'] = (sell_shares_advantage(market) * 100).round(2)
      result_details['expected_profit'] = (calculate_expected_profit(market) * 100).round(2)
      result_details['guaranteed_profit'] = (guaranteed_profit * 100).round(2)

      @results << result_details
    end


  end

  def calculate_guaranteed_profit(market)
    buy_no_prices = buy_no_prices(market).compact.sort

    return nil if buy_no_prices.length < 2

    profit_potential = 0

    lowest_price = buy_no_prices.pop

    profit_potential += (1.0 - lowest_price)

    buy_no_prices.each do |price|
      profit_potential += 0.9 * (1.0 - price)
    end

    profit_potential -= 1

    @should_play_alert = true if profit_potential > 0 && !ignore_markets.include?(market['id'].to_i)
    profit_potential
  end

  def calculate_expected_profit(market)
    probabilities = market['contracts'].map do |contract|
      if !contract['bestBuyNoCost']
        0.0
      elsif !contract['bestBuyYesCost']
        1.0
      else
        (contract['bestBuyYesCost'] + (1 - contract['bestBuyNoCost'])) / 2.0
      end
    end

    total_probability = probabilities.reduce(&:+)
    probabilities.map! {|p| p / total_probability }

    buy_no_prices = buy_no_prices(market)

    profit_potential = 0.0

    buy_no_prices.each_with_index do |loss_if_yes, index|
      next unless loss_if_yes

      yes_probability = probabilities[index]
      no_probability = 1.0 - yes_probability
      gain_if_no = 1.0 - loss_if_yes

      profit_potential += (0.9 * no_probability * gain_if_no) - (yes_probability * loss_if_yes)
    end

    profit_potential
  end

  def sell_shares_advantage(market)
    -market['contracts'].length + 1.0 + sell_no_prices(market).compact.reduce(&:+)
  end

  def buy_no_prices(market)
    market['contracts'].map do |contract|
      contract['bestBuyNoCost']
    end
  end

  def sell_no_prices(market)
    market['contracts'].map do |contract|
      contract['bestSellNoCost']
    end
  end

  def play_alert
    if @should_play_alert
      6.times do
        print "\a"
        sleep(1)
      end
    end
  end

  def ignore_markets
    [6653, 6941]
  end
end

PredictItAnalyzer.new.run
