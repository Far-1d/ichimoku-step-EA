//+------------------------------------------------------------------+
//|                                                ichimoku_step.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                        https://github.com/Far-1d |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://github.com/Far-1d"
#property version   "1.00"

//--- import library
#include <trade/trade.mqh>
CTrade trade;

//---inputs
input group "Ichimoku Config";
input int tenken              = 9;           // Tenken-sen 
input int kijun               = 26;          // Kijun-sen
input int senkou              = 52;          // Senkou Span B

input group "Strategy Config";
input int min_step_height     = 5;           // minimum step height in pip
input int min_step_flat       = 2;           // minimum step flat candles
input int candles_between     = 26;          // candles between steps
input int similarity          = 90;          // minimum similarity %
input int trade_distance      = 0;           // which future candle to trade (must be smaller than kijunsen number)
enum lines {
   SpanB=SENKOUSPANB_LINE,
   TenkenSen=TENKANSEN_LINE,
   KijunSen=KIJUNSEN_LINE
};
input lines refrence          = SpanB;       // refrence line
input lines copier            = TenkenSen;   // copier line
input bool use_third_line     = false;       // use third line
input lines third_line        = KijunSen;    // third line 

input group "Position Config";
input int Magic            = 5555;
enum lot_method {
   for_x_dollar_balance,
   constant
};
input lot_method lot_type  = constant;              // how to calculate lot size? 
input int dollar_balance   = 100;                   // base account dollar for balance and equity calculation
input double lot_value     = 0.1;                   // lot size
input int sl_distance      = 10;                    // sl distance in pip
enum tp_method {
   TP1,
   TP2,
   Trail,
   TP1_TP2,
   TP1_Trail,
   TP2_Trail,
   TP1_TP2_Trail
};
input tp_method tp_type = TP1_TP2_Trail;            // which tp to be active?(below inputs will be ignored based on active tp4)

input int tp1_distance     = 20;                    // tp 1 distance in pip
input int tp2_distance     = 30;                    // tp 2 and trail distance in pip
input int tp1_percent      = 50;                    // % percent of position to close at tp 1 
input int tp2_percent      = 30;                    // % percent of position to close at tp 2 
input int trail_percent    = 20;                    // % percent of position to close at trail 
input int trail_pip        = 30;                    // trail distance in pips when tp 2 reached
input bool tp2_at_last_candle = false;              // change tp2 to last candle open

input group "Risk free Config";
input bool use_rf          = false;                 // Enable Risk Free ?
input double rf_distance   = 5;                     // Price distance from entry (pip)


//--- global variables
int ichi_handle;
double lot_size;                                    // calculated initial lot size based on inputs
ulong last_tikt;


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(){
   ichi_handle = iIchimoku(_Symbol, PERIOD_CURRENT, tenken, kijun, senkou);
   
   // times license
   if (TimeCurrent() > StringToTime("2024-10-1")){
      Print("License finished, Please contact support");
      return(INIT_FAILED);
   }
   
   if(trade_distance > kijun){
      Print("future candles are larger than kijunsen number");
      return (INIT_FAILED);
   }
   
   trade.SetExpertMagicNumber(Magic);
   return(INIT_SUCCEEDED);
}
  
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){

   
}
  
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick(){
   static int totalbars = iBars(_Symbol, PERIOD_CURRENT);
   int bars = iBars(_Symbol, PERIOD_CURRENT);
   
   if (totalbars != bars)
   {
      if (!use_third_line)
      {
         check_ichi_step();
      }
      else
      {
         check_three_line_step();
      }
      
      totalbars = bars;
   }
   
}
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| check ichimoku for steps of two lines                            |
//+------------------------------------------------------------------+
void check_ichi_step(){
   double refrence_array[], copier_array[];
   ArraySetAsSeries(refrence_array, true);
   ArraySetAsSeries(copier_array, true);
   
   int future = kijun - trade_distance;
   if (refrence == SpanB) future -= kijun;
   CopyBuffer(ichi_handle, refrence, 1+future, 2, refrence_array);
   CopyBuffer(ichi_handle, copier, 1+candles_between+future, 2, copier_array);
   
   if (refrence == SpanB) future += kijun;
   
   double 
      refrence_step = NormalizeDouble(refrence_array[0] - refrence_array[1], _Digits),
      copier_step = NormalizeDouble(copier_array[0] - copier_array[1], _Digits);
   
   if (refrence_step != 0)
   {
      double curr_similarity=0;
      if (MathAbs(refrence_step) >= MathAbs(copier_step))
      {
         curr_similarity = NormalizeDouble((1 - (refrence_step-copier_step)/refrence_step)*100, 2);
      }
      else
      {
         curr_similarity = NormalizeDouble((1 - (copier_step-refrence_step)/copier_step)*100, 2);
      }
      // check step height
      if (MathAbs(refrence_step) >= min_step_height*10*_Point)
      {
         double line_value = refrence_array[1];
         int flat_candles = 0;
         for (int i=2; i<min_step_flat; i++){
            if (refrence_array[i] == line_value)
            {
               flat_candles ++;
            }
            else
            {
               break;
            }
         }
         
         // check step flat
         if (flat_candles >= min_step_flat)
         {
            // check flat similarity
            if (curr_similarity > similarity)
            {
               Print("----------   similar steps with ", curr_similarity, "% match.   ----------");
               Print("----------   flat = ", flat_candles, "   ----------");
               Print("----------   steps are: ", refrence_step, "     ", copier_step, "   ----------");
               
               double
                  close = iClose(_Symbol, PERIOD_CURRENT, 1+future),
                  open = iOpen(_Symbol, PERIOD_CURRENT, 1+future);
                  
               //--- calculate lot size
               if (lot_type == 1) lot_size = lot_value;
               else lot_size = lot_value*(AccountInfoDouble(ACCOUNT_BALANCE)/dollar_balance);
               
               if (close > open)
               {
                  open_position("SELL");
               }
               else if (close < open)
               {
                  open_position("BUY");
               }
               
            }
         }
      }
   }
   
}



//+------------------------------------------------------------------+
//| check ichimoku for steps of three lines                          |
//+------------------------------------------------------------------+
void check_three_line_step(){
   double refrence_array[], copier_array[], third_line_array[];
   ArraySetAsSeries(refrence_array, true);
   ArraySetAsSeries(copier_array, true);
   ArraySetAsSeries(third_line_array, true);
   
   int future = kijun - trade_distance;
   
   if (refrence == SpanB) future -= kijun;
   CopyBuffer(ichi_handle, refrence, 1+future,2, refrence_array);
   CopyBuffer(ichi_handle, copier, 1+candles_between+future,2, copier_array);
   CopyBuffer(ichi_handle, third_line, 1+candles_between+future,2, third_line_array);
   
   if (refrence == SpanB) future += kijun;
   
   double 
      refrence_step = NormalizeDouble(refrence_array[0] - refrence_array[1], _Digits),
      copier_step = NormalizeDouble(copier_array[0] - copier_array[1], _Digits),
      third_step = NormalizeDouble(third_line_array[0] - third_line_array[1], _Digits);
      
   if (refrence_step != 0)
   {
      double similarity1 = 0;
      double similarity2 = 0;
      
      if (MathAbs(refrence_step) >= MathAbs(copier_step))
      {
         similarity1 = NormalizeDouble((1 - (refrence_step-copier_step)/refrence_step)*100, 2);
      }
      else
      {
         similarity1 = NormalizeDouble((1 - (copier_step-refrence_step)/copier_step)*100, 2);
      }
      
      if (MathAbs(refrence_step) >= MathAbs(third_step))
      {
         similarity2 = NormalizeDouble((1 - (refrence_step-third_step)/refrence_step)*100, 2);
      }
      else
      {
         similarity2 = NormalizeDouble((1 - (third_step-refrence_step)/third_step)*100, 2);
      }
      
      
      // check step height
      if (MathAbs(refrence_step) >= min_step_height*10*_Point)
      {
         double line_value = refrence_array[1];
         int flat_candles = 0;
         for (int i=2; i<min_step_flat; i++){
            if (refrence_array[i] == line_value)
            {
               flat_candles ++;
            }
            else
            {
               break;
            }
         }
         
         // check step flat
         if (flat_candles >= min_step_flat)
         {
            // check flat similarity
            if (similarity1 > similarity && similarity2 > similarity)
            {
               
               Print("----------   similar steps with ", similarity1, "% And ", similarity2,"% match.   ----------");
               Print("----------   flat = ", flat_candles, "   ----------");
               Print("----------   steps are: ", refrence_step, "     ", copier_step, "     ", third_step, "   ----------");
               
               double
                  close = iClose(_Symbol, PERIOD_CURRENT, 1+future),
                  open = iOpen(_Symbol, PERIOD_CURRENT, 1+future);
                  
               //--- calculate lot size
               if (lot_type == 1) lot_size = lot_value;
               else lot_size = lot_value*(AccountInfoDouble(ACCOUNT_BALANCE)/dollar_balance);
               
               if (close > open)
               {
                  open_position("SELL");
               }
               else if (close < open)
               {
                  open_position("BUY");
               }
               
            }
            
         }
      
      }
      
   }   
      
      
}




//+------------------------------------------------------------------+
//| Open positions with requote resistant method                     |
//+------------------------------------------------------------------+
void open_position(string type){

   if (type == "BUY"){
      double 
         ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK),
         sl  = ask - (sl_distance*10*_Point),
         tp1 = ask + (tp1_distance*10*_Point),
         tp2 = ask + (tp2_distance*10*_Point),
         lt1 = NormalizeDouble(lot_size*tp1_percent/100, 2),
         lt2 = NormalizeDouble(lot_size*tp2_percent/100, 2),
         lt3 = NormalizeDouble(lot_size*trail_percent/100, 2);
         Print("ask = ", ask, "   sl = ", sl, "   tp1 = ", tp1, "   tp2 = ", tp2, "    lt1 = ", lt1);
      if (tp2_at_last_candle)
      {
         tp2 = iOpen(_Symbol, PERIOD_CURRENT, 1);
      }
      if (tp_type == 0){
         int counting = 0;
         while(true){
            if (place_order("BUY", lt1, sl, tp1)){
               Print("Only tp1 Buy Order Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
      } else if (tp_type == 1){
         int counting = 0;
         while(true){
            if (place_order("BUY", lt2, sl, tp2)){
               Print("Only tp2 Buy Order Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
      } else if (tp_type == 2){
         int counting = 0;
         while(true){
            if (place_order("BUY", lt3, sl, 0, "trail")){
               Print("Only trailing Buy Order Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
      } else if (tp_type == 3){
         int counting = 0;
         while(true){
            if (place_order("BUY", lt1, sl, tp1)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         while(true){
            if (place_order("BUY", lt2, sl, tp2)){
               Print("tp1 and tp2 Buy Orders Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
      
      } else if (tp_type == 4){
         int counting = 0;
         while(true){
            if (place_order("BUY", lt1, sl, tp1)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         while(true){
            if (place_order("BUY", lt3, sl, 0, "trail")){
               Print("tp1 and trail Buy Orders Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
      
      } else if (tp_type == 5){
         int counting = 0;
         while(true){
            if (place_order("BUY", lt2, sl, tp2)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         while(true){
            if (place_order("BUY", lt3, sl, 0, "trail")){
               Print("tp2 and trail Buy Orders Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
           
      } else if (tp_type == 6){
         int counting = 0;
         while(true){
            if (place_order("BUY", lt1, sl, tp1)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
         while(true){
            if (place_order("BUY", lt2, sl, tp2)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
         while(true){
            if (place_order("BUY", lt3, sl, 0, "trail")){
               Print("All Buy Orders Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
      }
      
   } else {
      double 
         bid = SymbolInfoDouble(_Symbol, SYMBOL_BID),
         sl  = bid + (sl_distance*10*_Point),
         tp1 = bid - (tp1_distance*10*_Point),
         tp2 = bid - (tp2_distance*10*_Point),
         lt1 = NormalizeDouble(lot_size*tp1_percent/100, 2),
         lt2 = NormalizeDouble(lot_size*tp2_percent/100, 2),
         lt3 = NormalizeDouble(lot_size*trail_percent/100, 2);
         Print("bid = ", bid, "   sl = ", sl, "   tp1 = ", tp1, "   tp2 = ", tp2, "    lt1 = ", lt1);
      if (tp2_at_last_candle)
      {
         tp2 = iOpen(_Symbol, PERIOD_CURRENT, 1);
      }
      if (tp_type == 0){
         int counting = 0;
         while(true){
            if (place_order("SELL", lt1, sl, tp1)){
               Print("Only tp1 Sell Order Entered @bid");
               break;
            } else counting ++;

            if (counting >= 10) break;
         }
         
      } else if (tp_type == 1){
         int counting = 0;
         while(true){
            if (place_order("SELL", lt2, sl, tp2)){
               Print("Only tp2 Sell Order Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
      } else if (tp_type == 2){
         int counting = 0;
         while(true){
            if (place_order("SELL", lt3, sl, 0, "trail")){
               Print("Only trailing Sell Order Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
      } else if (tp_type == 3){
         int counting = 0;
         while(true){
            if (place_order("SELL", lt1, sl, tp1)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
         while(true){
            if (place_order("SELL", lt2, sl, tp2)){
               Print("tp1 and tp2 Sell Order Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
      } else if (tp_type == 4){
         int counting = 0;
         while(true){
            if (place_order("SELL", lt1, sl, tp1)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
         while(true){
            if (place_order("SELL", lt3, sl, 0, "trail")){
               Print("tp1 and trail Sell Order Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
      } else if (tp_type == 5){
         int counting = 0;
         while(true){
            if (place_order("SELL", lt2, sl, tp2)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
         while(true){
            if (place_order("SELL", lt3, sl, 0, "trail")){
               Print("tp2 and trail Sell Order Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
      } else if (tp_type == 6){
         int counting = 0;
         while(true){
            if (place_order("SELL", lt1, sl, tp1)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
         while(true){
            if (place_order("SELL", lt2, sl, tp2)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
         while(true){
            if (place_order("SELL", lt3, sl, 0, "trail")){
               Print("All Sell Orders Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }

      }
   }
}


//+------------------------------------------------------------------+
//| Place orders from values returned from open_position()           |
//+------------------------------------------------------------------+
bool place_order(string type, double lots, double sl, double tp, string comment=""){
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK); 
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   Print("placing orders");
   
   if (lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN) && lots>0){
      lots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   }
   
   int parts = 1;
   //if (lots > max_lot){
   //   parts = ( int )MathFloor(lots/max_lot) + 1;
   //} 

   if (type == "BUY"){
   //   for (int i=0; i<parts; i++){
   //      trade.Buy(NormalizeDouble(lots/parts, 2), _Symbol, 0, sl, tp, comment);
   //   }
      if (trade.Buy(lots, _Symbol, 0, sl, tp, comment))
      {
         int tot = PositionsTotal();
         last_tikt = PositionGetTicket(tot-1);
         //last_tikt = trade.ResultDeal();
         return true;
      }
      
   } else {
      //for (int i=0; i<parts; i++){
      //   trade.Sell(NormalizeDouble(lots/parts, 2), _Symbol, 0, sl, tp, comment);
      //}
      if (trade.Sell(lots, _Symbol, 0, sl, tp, comment))
      {
         int tot = PositionsTotal();
         last_tikt = PositionGetTicket(tot-1);
         //last_tikt = trade.ResultDeal();
         return true;
      }
      
   }
   return false;
}


//+------------------------------------------------------------------+
//| trailing function                                                |
//+------------------------------------------------------------------+
void trailing(ulong tikt , string type){
   PositionSelectByTicket(tikt);
   double entry         = PositionGetDouble(POSITION_PRICE_OPEN);
   double curr_sl       = PositionGetDouble(POSITION_SL);
   double curr_tp       = PositionGetDouble(POSITION_TP); 
   double ask           = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid           = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if(type == "BUY"){
      if (ask > PositionGetDouble(POSITION_PRICE_OPEN)+(tp2_distance*10*_Point)){
         if (ask-curr_sl > trail_pip*10*_Point){
            trade.PositionModify(tikt, ask - trail_pip*10*_Point, curr_tp);
            Print("changed buy trailed to ", ask - trail_pip*10*_Point);
         }
      }
   } else {
      if (bid < PositionGetDouble(POSITION_PRICE_OPEN)-(tp2_distance*10*_Point)){
         if (curr_sl-bid > trail_pip*10*_Point){
            trade.PositionModify(tikt, bid + trail_pip*10*_Point, curr_tp);
            Print("changed sell trailed to ", bid + trail_pip*10*_Point);
         }
      }
   }
   
}

//+----------------------------------------------------------------------+
//| this function riskfrees positions no matter if trailing is active    |
//+----------------------------------------------------------------------+
void riskfree(ulong tikt){
   if (use_rf) {
      //PositionSelectByTicket(tikt)
      double
         entry = PositionGetDouble(POSITION_PRICE_OPEN),
         tp = PositionGetDouble(POSITION_TP),
         sl = PositionGetDouble(POSITION_SL),
         ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK),
         bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      long pos_type = PositionGetInteger(POSITION_TYPE);
      
      double comission_price = calculate_comission_for_riskfree(tikt);
     
      if (pos_type == POSITION_TYPE_BUY){
         if (ask - entry >= rf_distance*10*_Point && sl < entry){
            trade.PositionModify(tikt, entry+comission_price, tp);
            Print("buy position riskfreed to ", entry);
         }
      }
      
      if (pos_type == POSITION_TYPE_SELL){
         if (entry - bid >= rf_distance*10*_Point && sl > entry){
            trade.PositionModify(tikt, entry-comission_price, tp);
            Print("sell position riskfreed to ", entry);
         }
      }
   }
}

//+-------------------------------------------------------------------------------------------------+
//| calculate the price change needed to make for the comission fee , riskfree must have zero loss  |
//+-------------------------------------------------------------------------------------------------+
double calculate_comission_for_riskfree(ulong tikt){
   HistoryDealSelect(tikt);
   double comission  = HistoryDealGetDouble(tikt, DEAL_COMMISSION);
   double volume     = HistoryDealGetDouble(tikt, DEAL_VOLUME);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   double points = MathAbs((2*comission)/(volume*tick_value));
   
   return NormalizeDouble(points*_Point, _Digits);
}