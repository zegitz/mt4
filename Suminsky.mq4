//+------------------------------------------------------------------+
//|                                                     Suminsky.mq4 |
//|                                                        José Gitz |
//|                                                 zegitz@gmail.com |
//+------------------------------------------------------------------+
#property copyright "By Zé Gitz"
#property link "http://fb.com/zegitz"
#property version "1.0"
#property description "Estratégia de Suminsky"

#include <stdlib.mqh>
#include <stderror.mqh>

//enum Tipo
//   {
//T_1 = OP_BUY,//Only Buy
//T_2 = OP_SELL,//Only Sell
//   };
//input Tipo EA_Type = OP_SELL;
extern bool Trailing = false;
extern double Trail_Points = 10;
extern double Trail_Step = 5;
extern double Range = 3500;
extern double Linhas = 35;
extern double TakeProfit = 35;
extern bool CloseOnBid = true;
extern double Lot = 0.01;
double PontoBase;
extern int TotalOrders = 3;
int LotDigits; //initialized in OnInit
extern int MagicNumber = 12345;
int MaxSlippage = 3; //adjusted in OnInit
int MaxPendingOrders = 1000;
int MaxSpread = 100;
bool Hedging = true;
int OrderRetry = 5;   //# of retries if sending order returns error
int OrderWait = 5;    //# of seconds to wait if sending order returns error
double myPoint = 0.0; //initialized in OnInit
int LastClosedOrder = 0;
int closedOrdersCount = 0;

void myAlert(string type, string message)
{
  if (type == "print")
    Print(message);
  else if (type == "error")
  {
    Print(type + " | EA_ALI_COPIA @ " + Symbol() + "," + Period() + " | " + message);
  }
  else if (type == "order")
  {
    Print(message);
  }
  else if (type == "modify")
  {
    Print(message);
  }
}

int TradesCount(int type) //returns # of open trades for order type, current symbol and magic number
{
  int result = 0;
  int total = OrdersTotal();
  for (int i = 0; i < total; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == false)
      continue;
    if (OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol() || OrderType() != type)
      continue;
    result++;
  }
  return (result);
}

int myOrderSend(int type, double price, double volume, string ordername) //send order, return ticket ("price" is irrelevant for market orders)
{
  int ticket = -1;
  int retries = 0;
  int err;
  int long_trades = TradesCount(OP_BUY);
  int short_trades = TradesCount(OP_SELL);
  int long_pending = TradesCount(OP_BUYLIMIT) + TradesCount(OP_BUYSTOP);
  int short_pending = TradesCount(OP_SELLLIMIT) + TradesCount(OP_SELLSTOP);
  string ordername_ = ordername;
  if (ordername != "")
    ordername_ = "(" + ordername + ")";
  //test Hedging
  if (!Hedging && ((type % 2 == 0 && short_trades + short_pending > 0) || (type % 2 == 1 && long_trades + long_pending > 0)))
  {
    myAlert("print", "Order" + ordername_ + " not sent, hedging not allowed");
    return (-1);
  }

  //prepare to send order
  while (IsTradeContextBusy())
    Sleep(100);
  RefreshRates();
  if (type == OP_BUY)
    price = Ask;
  else if (type == OP_SELL)
    price = Bid;
  else if (price < 0) //invalid price for pending order
  {
    myAlert("order", "Order" + ordername_ + " not sent, invalid price for pending order");
    return (-1);
  }
  int clr = (type % 2 == 1) ? clrRed : clrBlue;
  if (MaxSpread > 0 && Ask - Bid > MaxSpread * myPoint)
  {
    myAlert("order", "Order" + ordername_ + " not sent, maximum spread " + DoubleToStr(MaxSpread * myPoint, Digits()) + " exceeded");
    return (-1);
  }
  while (ticket < 0 && retries < OrderRetry + 1)
  {
    ticket = OrderSend(Symbol(), type, NormalizeDouble(volume, LotDigits), NormalizeDouble(price, Digits()), MaxSlippage, 0, 0, ordername, MagicNumber, 0, clr);
    if (ticket < 0)
    {
      err = GetLastError();
      myAlert("print", "OrderSend" + ordername_ + " error #" + err + " " + ErrorDescription(err));
      Sleep(OrderWait * 1000);
    }
    retries++;
  }
  if (ticket < 0)
  {
    myAlert("error", "OrderSend" + ordername_ + " failed " + (OrderRetry + 1) + " times; error #" + err + " " + ErrorDescription(err));
    return (-1);
  }
  // string typestr[6] = {"Buy", "Sell", "Buy Limit", "Sell Limit", "Buy Stop", "Sell Stop"};
  // myAlert("order", "Order sent" + ordername_ + ": " + typestr[type] + " " + Symbol() + " Magic #" + MagicNumber);
  return (ticket);
}

int myOrderModify(int ticket, double SL, double TP) //modify SL and TP (absolute price), zero targets do not modify
{
  if (!IsTradeAllowed())
    return (-1);
  bool success = false;
  int retries = 0;
  int err;
  SL = NormalizeDouble(SL, Digits());
  TP = NormalizeDouble(TP, Digits());
  if (SL < 0)
    SL = 0;
  if (TP < 0)
    TP = 0;
  //prepare to select order
  while (IsTradeContextBusy())
    Sleep(100);
  if (!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
  {
    err = GetLastError();
    myAlert("error", "OrderSelect failed; error #" + err + " " + ErrorDescription(err));
    return (-1);
  }
  //prepare to modify order
  while (IsTradeContextBusy())
    Sleep(100);
  RefreshRates();
  if (CompareDoubles(SL, 0))
    SL = OrderStopLoss(); //not to modify
  if (CompareDoubles(TP, 0))
    TP = OrderTakeProfit(); //not to modify
  if (CompareDoubles(SL, OrderStopLoss()) && CompareDoubles(TP, OrderTakeProfit()))
    return (0); //nothing to do
  while (!success && retries < OrderRetry + 1)
  {
    success = OrderModify(ticket, NormalizeDouble(OrderOpenPrice(), Digits()), NormalizeDouble(SL, Digits()), NormalizeDouble(TP, Digits()), OrderExpiration(), CLR_NONE);
    if (!success)
    {
      err = GetLastError();
      myAlert("print", "OrderModify error #" + err + " " + ErrorDescription(err));
      Sleep(OrderWait * 1000);
    }
    retries++;
  }
  if (!success)
  {
    myAlert("error", "OrderModify failed " + (OrderRetry + 1) + " times; error #" + err + " " + ErrorDescription(err));
    return (-1);
  }
  string alertstr;
  if (!CompareDoubles(SL, 0))
    alertstr = alertstr + " SL=" + SL;
  if (!CompareDoubles(TP, 0))
    alertstr = alertstr + " TP=" + TP;
  // myAlert("modify", alertstr);
  return (0);
}

int myOrderModifyRel(int ticket, double SL, double TP) //modify SL and TP (relative to open price), zero targets do not modify
{
  if (!IsTradeAllowed())
    return (-1);
  bool success = false;
  int retries = 0;
  int err;
  SL = NormalizeDouble(SL, Digits());
  TP = NormalizeDouble(TP, Digits());
  if (SL < 0)
    SL = 0;
  if (TP < 0)
    TP = 0;
  //prepare to select order
  while (IsTradeContextBusy())
    Sleep(100);
  if (!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
  {
    err = GetLastError();
    myAlert("error", "OrderSelect failed; error #" + err + " " + ErrorDescription(err));
    return (-1);
  }
  //prepare to modify order
  while (IsTradeContextBusy())
    Sleep(100);
  RefreshRates();
  //convert relative to absolute
  if (OrderType() % 2 == 0) //buy
  {
    if (NormalizeDouble(SL, Digits()) != 0)
      SL = OrderOpenPrice() - SL;
    if (NormalizeDouble(TP, Digits()) != 0)
      TP = OrderOpenPrice() + TP;
  }
  else //sell
  {
    if (NormalizeDouble(SL, Digits()) != 0)
      SL = OrderOpenPrice() + SL;
    if (NormalizeDouble(TP, Digits()) != 0)
      TP = OrderOpenPrice() - TP;
  }
  if (CompareDoubles(SL, 0))
    SL = OrderStopLoss(); //not to modify
  if (CompareDoubles(TP, 0))
    TP = OrderTakeProfit(); //not to modify
  if (CompareDoubles(SL, OrderStopLoss()) && CompareDoubles(TP, OrderTakeProfit()))
    return (0); //nothing to do
  while (!success && retries < OrderRetry + 1)
  {
    success = OrderModify(ticket, NormalizeDouble(OrderOpenPrice(), Digits()), NormalizeDouble(SL, Digits()), NormalizeDouble(TP, Digits()), OrderExpiration(), CLR_NONE);
    if (!success)
    {
      err = GetLastError();
      myAlert("print", "OrderModify error #" + err + " " + ErrorDescription(err));
      Sleep(OrderWait * 1000);
    }
    retries++;
  }
  if (!success)
  {
    myAlert("error", "OrderModify failed " + (OrderRetry + 1) + " times; error #" + err + " " + ErrorDescription(err));
    return (-1);
  }
  string alertstr = "Order modified: ticket=" + ticket;
  if (!CompareDoubles(SL, 0))
    alertstr = alertstr + " SL=" + SL;
  if (!CompareDoubles(TP, 0))
    alertstr = alertstr + " TP=" + TP;
  // myAlert("modify", alertstr);
  return (0);
}

void TrailingStopTrail(int type, double TS, double step, bool aboveBE) //set Stop Loss to "TS" if price is going your way with "step"
{
  int total = OrdersTotal();
  TS = NormalizeDouble(TS, Digits());
  step = NormalizeDouble(step, Digits());
  for (int i = total - 1; i >= 0; i--)
  {
    while (IsTradeContextBusy())
      Sleep(100);
    if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      continue;
    if (OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol() || OrderType() != type)
      continue;
    RefreshRates();
    if (type == OP_BUY && (!aboveBE || Ask > OrderOpenPrice() + TS) && (NormalizeDouble(OrderStopLoss(), Digits()) <= 0 || Ask > OrderStopLoss() + TS + step))
      myOrderModify(OrderTicket(), Ask - TS, 0);
    else if (type == OP_SELL && (!aboveBE || Bid < OrderOpenPrice() - TS) && (NormalizeDouble(OrderStopLoss(), Digits()) <= 0 || Bid < OrderStopLoss() - TS - step))
      myOrderModify(OrderTicket(), Bid + TS, 0);
  }
}
void myOrderClose(int type, int volumepercent, string ordername) //close open orders for current symbol, magic number and "type" (OP_BUY or OP_SELL)
{
  if (!IsTradeAllowed())
    return;
  if (type > 1)
  {
    myAlert("error", "Invalid type in myOrderClose");
    return;
  }
  bool success = false;
  int err;
  string ordername_ = ordername;
  if (ordername != "")
    ordername_ = "(" + ordername + ")";
  int total = OrdersTotal();
  for (int i = total - 1; i >= 0; i--)
  {
    while (IsTradeContextBusy())
      Sleep(100);
    if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      continue;
    if (OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol() || OrderType() != type)
      continue;
    while (IsTradeContextBusy())
      Sleep(100);
    RefreshRates();
    double price = (type == OP_SELL) ? Ask : Bid;
    double volume = NormalizeDouble(OrderLots() * volumepercent * 1.0 / 100, LotDigits);
    if (NormalizeDouble(volume, LotDigits) == 0)
      continue;
    success = OrderClose(OrderTicket(), volume, NormalizeDouble(price, Digits()), MaxSlippage, clrWhite);
    if (!success)
    {
      err = GetLastError();
      myAlert("error", "OrderClose" + ordername_ + " failed; error #" + err + " " + ErrorDescription(err));
    }
  }
  string typestr[6] = {"Buy", "Sell", "Buy Limit", "Sell Limit", "Buy Stop", "Sell Stop"};
  if (success)
    myAlert("order", "Orders closed" + ordername_ + ": " + typestr[type] + " " + Symbol() + " Magic #" + MagicNumber);
}

void Painel()
{
  ObjectCreate("email", OBJ_LABEL, 0, 0, 0);
  ObjectSet("email", OBJPROP_XDISTANCE, 10);
  ObjectSet("email", OBJPROP_YDISTANCE, 12);
  ObjectSetText("email", "zegitz@gmail.com", 8, "Arial Black", Gray);
  ObjectCreate("logo", OBJ_LABEL, 0, 0, 0);
  ObjectSet("logo", OBJPROP_XDISTANCE, 10);
  ObjectSet("logo", OBJPROP_YDISTANCE, 25);
  ObjectSetText("logo", "Estratégia", 8, "Arial Black", Yellow);
}

int AbrePosicao(double price, int type)
{
  int ticket = -1;
  RefreshRates();
  int multiplier = (type == OP_BUY || type == OP_BUYLIMIT || type == OP_BUYSTOP) ? 1 : -1; // multiplicador determina + para Buy - para Sell
  ticket = myOrderSend(type, price, Lot, type);
  if (ticket <= 0)
    return -1;

  double TP = price + (TakeProfit * myPoint * multiplier); //Take Profit = value in points (relative to price)
  myOrderModify(ticket, 0, TP);

  return ticket;
}

void inicio(int type)
{
  if (type == OP_SELL)
  {
    AbrePosicao(Ask, OP_SELL);
    AbrePosicao(Ask + (Linhas * myPoint), OP_SELLLIMIT);
    AbrePosicao(Ask - (Linhas * myPoint), OP_SELLSTOP);
  }
  if (type == OP_BUY)
  {
    AbrePosicao(Bid, OP_BUY);
    AbrePosicao(Bid + (Linhas * myPoint), OP_BUYLIMIT);
    AbrePosicao(Bid - (Linhas * myPoint), OP_BUYSTOP);
  }
}

double HighestSellPoint()
{
  double Value = 0;
  int total = OrdersTotal();
  for (int i = 0; i < total; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == false)
      continue;
    if (OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
      continue;
    if (OrderOpenPrice() > Value)
    {
      Value = OrderOpenPrice();
    }
  }
  return (Value);
}

double LowestSellPoint()
{
  double Value = 10;
  int total = OrdersTotal();
  for (int i = 0; i < total; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == false)
      continue;
    if (OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
      continue;
    if (OrderOpenPrice() < Value)
    {
      Value = OrderOpenPrice();
    }
  }
  return (Value);
}

void ReopenLastClosedOrder()
{
  int i, hstTotal = OrdersHistoryTotal();
  // printf("------------ Search order history [%i]", hstTotal);
  for (i = 0; i < hstTotal; i++)
  {
    // printf("Reopen Last Order %i",i);
    if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY) == false)
      continue;
    //  printf("Ordem selecionada %i",i);
    if (OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
      continue;
    // printf("selected Ticket %i : Last %i",OrderTicket(),LastClosedOrder);
    if (OrderTicket() > LastClosedOrder)
    {
      int ticket = OrderTicket();
      if (ReopenClosedOrder(ticket) > 0)
      {
        //printf("Tudo certo, reabriu last closed order %i : LastClosedOrder agora = %i", LastClosedOrder, ticket);
        LastClosedOrder = ticket;
        return;
      }
    }
  }
}

// verifies if an order was closed
void FindClosedOrderEx()
{

  // number of closed orders increased?
  int count = OrdersHistoryTotal();
  if (count > closedOrdersCount)
  {
    // yes, then lets get the latest

    if (!OrderSelect(count - 1, SELECT_BY_POS, MODE_HISTORY))
    {
      int err = GetLastError();
      myAlert("error", "OrderSelect failed; error #" + err + " " + ErrorDescription(err));
      return;
    }

    // and reopen it!
    int ticket = OrderTicket();
    if (ReopenClosedOrder(ticket) > 0)
    {
      //printf("Tudo certo, reabriu last closed order %i : LastClosedOrder agora = %i", LastClosedOrder, ticket);
    }

    // update closed orders count
    closedOrdersCount = count;
  }
}

int ReopenClosedOrder(int ticket)
{
  //find last closed order ticket and clone it
  double lastprice = 0;
  ResetLastError();
  int lasttype;
  //printf("[ReopenClosedOrder] search for ticket ( %i )", ticket);

  if (OrderSelect(ticket, SELECT_BY_TICKET) == true)
  {
    lastprice = OrderOpenPrice();
    lasttype = OrderType();
    //printf("Ultima ordem %i - ultimo preço %f - ultimo Tipo: %i", ticket, lastprice, lasttype);

    int total = OrdersTotal();
    for (int i = 0; i < total; i++)
    {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == false)
        continue;
      if (OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
        continue;
      if (OrderOpenPrice() == lastprice)
      {
        //printf("Encontrou Ordem com mesmo preço %f no ticket %i", lastprice, ticket);
        return false;
      }
      //printf("Ordem na posição [%i] com preço (%f) não corresponde ao last price (%f)", i, OrderOpenPrice(), lastprice);

    } // se terminou o for , não encontrou ordem aberta na posição lastprice , reopen order
    //printf("Não achou ordem aberta com esse preço (%f), vai abrir ordem", lastprice);
    return AbrePosicao(lastprice, GetStopLimitType(lastprice, lasttype));
  }
  else
  {
    printf("Não achou o ticket");
    int err = GetLastError();
    myAlert("print", "OrderSend error #" + err + " " + ErrorDescription(err));
  }
  return false;
}

int GetStopLimitType(double price, int type)
{
  if (type == OP_SELL || type == OP_SELLLIMIT || type == OP_SELLSTOP)
  {
    return price > Bid ? OP_SELLLIMIT : OP_SELLSTOP;
  }
  else
  {
    return price > Bid ? OP_BUYSTOP : OP_BUYLIMIT;
  }
}

void AbreOrdensPontas()
{
  int SellLimit_Orders = TradesCount(OP_SELLLIMIT);
  int SellStop_Orders = TradesCount(OP_SELLSTOP);

  if (SellLimit_Orders == 0)
  {
    AbrePosicao(HighestSellPoint() + (Linhas * myPoint), OP_SELLLIMIT);
  }
  if (SellStop_Orders == 0)
  {
    AbrePosicao(LowestSellPoint() - (Linhas * myPoint), OP_SELLSTOP);
  }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  //initialize myPoint
  myPoint = Point();
  PontoBase = Bid;
  if (Digits() == 5 || Digits() == 3)
  {
    myPoint *= 10;
    MaxSlippage *= 10;
  }
  //initialize LotDigits
  double LotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
  if (LotStep >= 1)
    LotDigits = 0;
  else if (LotStep >= 0.1)
    LotDigits = 1;
  else if (LotStep >= 0.01)
    LotDigits = 2;
  else
    LotDigits = 3;
  inicio(OP_SELL);
  return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  ObjectDelete("logo");
  ObjectDelete("email");
  ObjectDelete("cross");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()

{
  AbreOrdensPontas();
  //ReopenLastClosedOrder();
  FindClosedOrderEx();
}
//+------------------------------------------------------------------+
