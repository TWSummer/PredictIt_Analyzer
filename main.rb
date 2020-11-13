require 'net/http'
require 'json'
require 'date'
require 'active_support/time'

class PredictItAnalyzer
  MAXED_MARKETS = [6653, 6941, 6950].freeze
  EXPECTED_ANNUAL_RETURN = 0.4 # Expect 40% annual return on investment (continually compounding)

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
    sort_results('expected_profit')
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
        puts "#{k}: #{v}".send(color(result))
      end
    end
  end

  def sort_results(sort_field='guaranteed_profit')
    @results.sort! do |a, b|
      # Sort any markets with sell_shares_advantage > 0 to the end of the list, otherwise sort by sort_field
      a_value = a['sell_shares_advantage'] && a['sell_shares_advantage'] > 0 ? 1000 : a[sort_field]
      b_value = b['sell_shares_advantage'] && b['sell_shares_advantage'] > 0 ? 1000 : b[sort_field]

      a_value <=> b_value
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
      result_details['expected_profit'] = (calculate_expected_profit(market) * 100).round(2)
      result_details['guaranteed_profit'] = (guaranteed_profit * 100).round(2)

      if (MAXED_MARKETS.include?(result_details['id'])) # For maxed markets, check if it is better to sell shares now
        result_details['sell_shares_advantage'] = (sell_shares_advantage(market) * 100).round(2)
        if result_details['sell_shares_advantage'] > 0
          result_details['current_sell_no_prices'] = sell_no_prices(market).compact.map {|p| (p * 100).round }
        end
      elsif (result_details['expected_profit'] > 0 && result_details['guaranteed_profit'] < 0)
        # For markets with positive expected profit, but no guaranteed profit determine how long term it is worth having money invested for
        result_details['worth_purchasing_if_market_resolves_by'] =
          Date.today +
          (Math.log((result_details['guaranteed_profit'] - result_details['expected_profit']) / result_details['guaranteed_profit']) / EXPECTED_ANNUAL_RETURN * 365.0).to_i.days
      end

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

    @should_play_alert = true if profit_potential >= 0.01 && !MAXED_MARKETS.include?(market['id'])
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
    result = -market['contracts'].length + 1.0 + sell_no_prices(market).compact.reduce(&:+)

    @should_play_alert = true if result > 0.01

    result
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
      12.times do
        print "\a"
        sleep(0.25)
      end
    end
  end

  def MAXED_MARKETS
    [6653, 6941, 6950]
  end

  def color(result)
    case true
    when MAXED_MARKETS.include?(result['id'])
      :blue
    when result['guaranteed_profit'] > 0.01
      :green
    when result['sell_shares_advantage'] && result['sell_shares_advantage'] > 0.01
      :pink
    when result['expected_profit'] > 0.01
      :yellow
    else
      :red
    end
  end
end

class String
  # colorization
  def colorize(color_code)
    "\e[#{color_code}m#{self}\e[0m"
  end

  def red
    colorize(31)
  end

  def green
    colorize(32)
  end

  def yellow
    colorize(33)
  end

  def blue
    colorize(34)
  end

  def pink
    colorize(35)
  end

  def light_blue
    colorize(36)
  end
end

PredictItAnalyzer.new.run
