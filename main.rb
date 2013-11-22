require 'rubygems'
require 'sinatra'

set :sessions, true

BLACKJACK_AMOUNT = 21
DEALER_MIN_HIT = 17
INITIAL_POT_AMOUNT = 500

helpers do # in helper, both request and views can use the method within
  def calculate_total(cards) # cards is [["H", "3"], ["D", "J"], ... ]
    arr = cards.map{|element| element[1]}

    total = 0
    arr.each do |a|
      if a == "A"
        total += 11
      else
        total += a.to_i == 0 ? 10 : a.to_i
      end
    end

    #correct for Aces
    arr.select{|element| element == "A"}.count.times do
      break if total <= BLACKJACK_AMOUNT
      total -= 10
    end

    total
  end

  def card_image(card) #['H', '4']
    suit = case card[0]
      when 'H' then 'hearts'
      when 'D' then 'diamonds'
      when 'C' then 'clubs'
      when 'S' then 'spades'
    end

    value = card[1]
    if ['J', 'Q', 'K', 'A'].include?(value)
      value = case card[1]
        when 'J' then 'jack'
        when 'Q' then 'queen'
        when 'K' then 'king'
        when 'A' then 'ace'
      end
    end

    "<img src='/images/cards/#{suit}_#{value}.jpg' class='card_image'>"

  end

  def winner!(msg)
    @play_again = true
    @show_hit_or_stay_buttons = false
    session[:player_pot] = session[:player_pot] + session[:player_bet] 
    @success = "<strong>#{session[:player_name]} wins!</strong> #{msg}"
  end

  def loser!(msg)
    @play_again = true
    @show_hit_or_stay_buttons = false
    session[:player_pot] = session[:player_pot] - session[:player_bet] 
    @error = "<strong>#{session[:player_name]} loses.</strong> #{msg}"
  end

  def tie!(msg)
    @play_again = true
    @show_hit_or_stay_buttons = false
    @success = "<strong>It's a tie!</strong> #{msg}"
  end

end

# in order to remove the 2 buttons once there is checked, we can use a filter "before"
# "before" means to put and run some code before further action.
before do
  # that is, we will put below instance variable boolean into every method in line 1
  # this give us the ability to set it to false where we want it to.
  # here we will put that in the hit & stay method.
  @show_hit_or_stay_buttons = true
end

get '/' do
  if session[:player_name] # session is to save variables in cookie
    redirect '/game'
  else
    redirect '/new_player' # redirect to another action to GET the page /newplayer
  end
end

get '/new_player' do
  session[:player_pot] = INITIAL_POT_AMOUNT
  erb :new_player # to create an erb @ views and in that new_player.erb, we will have a form to collect player_name
end

# so we are back from the new_player.erb to handle what we got from that page.
post '/new_player' do
  # here we want to check if user enter a name, if no, we use "halt" to stop the program and go to the following action
  if params[:player_name].empty?
    @error = "Name is required"
    halt erb(:new_player)
  end

  # the params will clear/disappear with every new request, so we need to save it in sessions with key=:player_name
  session[:player_name] = params[:player_name]
  # now we can progress to the game
  redirect '/bet'
end

get '/bet' do
  session[:player_bet] = nil
  erb :bet
end

post '/bet' do
  if params[:bet_amount].nil? || params[:bet_amount].to_i == 0
    @error = "Must make a bet."
    halt erb(:bet)
  elsif params[:bet_amount].to_i > session[:player_pot]
    @error = "Bet amount cannot be greater than what you have (#{session[:player_pot]})."
    halt erb(:bet)
  else
    session[:player_bet] = params[:bet_amount].to_i
    redirect '/game'
  end
end


get '/game' do
  session[:turn] = session[:player_name]

  # create a deck and put it in session
  suits = ['H', 'D', 'C', 'S']
  values = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A']
  session[:deck] = suits.product(values).shuffle! # [ ['H', '9'], ['C', 'K'] ... ]

  # deal cards
  session[:dealer_cards] = []
  session[:player_cards] = []
  session[:dealer_cards] << session[:deck].pop
  session[:player_cards] << session[:deck].pop
  session[:dealer_cards] << session[:deck].pop
  session[:player_cards] << session[:deck].pop

  # create a page "game" in views
  erb :game
end

post '/game/player/hit' do
  session[:player_cards] << session[:deck].pop

  player_total = calculate_total(session[:player_cards])
  if player_total == BLACKJACK_AMOUNT
    winner!("#{session[:player_name]} hit blackjack.")
  elsif player_total > BLACKJACK_AMOUNT
    loser!("It looks like #{session[:player_name]} busted at #{player_total}.")
  end
  # here we "render" tha game page again but not "redirect" since redirect will put us to line 53 and reset everything.
  erb :game
end

post '/game/player/stay' do
  @success = "#{session[:player_name]} has chosen to stay."
  @show_hit_or_stay_buttons = false
  # so the first step is to think how dealer's turn begin.
  # 1. player choose to stay(eventually player will)
  # 2. redirect to the page for dealer's turn
  # so we need redirect but not a simple render
  redirect "/game/dealer"
end

get '/game/dealer' do
  session[:turn] = "dealer"
  # first we cancel the "hit" and "stay" button
  @show_hit_or_stay_buttons = false
  # then we check dealer's hand of the first 2 cards if hit blackjack or busted
  dealer_total = calculate_total(session[:dealer_cards])
  
  if dealer_total == BLACKJACK_AMOUNT
    loser!("Dealer hit blackjack.")
  elsif dealer_total > BLACKJACK_AMOUNT
    winner!("Dealer busted at #{dealer_total}.")
  elsif dealer_total >= DEALER_MIN_HIT  #17, 18, 19, 20
    redirect '/game/compare'
  else
    # if the first 2 cards are not blackjack or busted, we show a button for player to push to see dealer's next hit
    @show_dealer_hit_button = true
  end  

  erb :game
end

post '/game/dealer/hit' do
  session[:dealer_cards] << session[:deck].pop
  redirect '/game/dealer' 
end

get '/game/compare' do
  @show_hit_or_stay_buttons = false

  player_total = calculate_total(session[:player_cards])
  dealer_total = calculate_total(session[:dealer_cards])

  if player_total < dealer_total
    loser!("#{session[:player_name]} stayed at #{player_total}, and the dealer stayed at #{dealer_total}.")
  elsif player_total > dealer_total
    winner!("#{session[:player_name]} stayed at #{player_total}, and the dealer stayed at #{dealer_total}.")
  else
    tie!("Both #{session[:player_name]} and the dealer stayed at #{player_total}.")
  end

  erb :game  
end

get '/game_over' do
  erb :game_over
end