//
//  StockfishLib.m
//  ChessHeaven
//
//  Created by Vickson on 10/09/2020.
//  Copyright © 2020 Madness. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <iostream>

#include "Bitboard.h"
#include "Position.h"
#include "search.h"
#include "uci.h"
#include "thread.h"
#include "pawn.h"
#include "psqt.h"

// One-time flags for this process
static bool gEngineInitialized  = false;
static bool gThreadsInitialized = false;

@interface StockfishLib : NSObject
- (void)initEngineIfNeeded:(double)skill :(double)time;
- (void)init:(double)skill :(double)time;
- (void)init:(double)skill :(double)time :(const char*)customFEN;
- (void)setPosition:(const char*)fen;
- (void)callMove:(int)from :(int)to;
- (void)castleMove:(int)castleSide;
- (void)enpassantMove:(int)from;
- (void)promotionMove:(int)from :(int)to :(int)promoType;
- (int)searchMove;
- (void)undoMove;
- (void)newGame;
- (bool)drawCheck;
- (void)releaseResource;
@end

@implementation StockfishLib {
    Position        _pos;
    StateListPtr    _states;
    std::deque<Move> _moveHistory;
    double          _skill;
    double          _time;
}

- (void)initEngineIfNeeded:(double)skill :(double)time
{
    if (!gEngineInitialized)
    {
        // One-time global engine init (Stockfish bootstrap)
        UCI::init(Options, skill, time);
        PSQT::init();
        Bitboards::init();
        Position::init();
        Bitbases::init();
        Search::init();
        Pawns::init();

        if (!gThreadsInitialized)
        {
            Threads.set(Options["Threads"]);   // OR hardcode 1/2 threads if you prefer
            gThreadsInitialized = true;
        }

        Search::clear(); // after threads are up

        gEngineInitialized = true;
        std::cout << "Stockfish global init done\n";
    }
}

- (void)init:(double)skill :(double)time
{
    [self initEngineIfNeeded:skill :time];

    _skill = skill;
    _time  = time;

    // Default starting position
    UCI::init(_pos, _states);
    std::cout << "Stockfish position init (default) skill=" << skill
              << " time=" << time << "\n";
}

- (void)init:(double)skill :(double)time :(const char*)customFEN
{
    [self initEngineIfNeeded:skill :time];

    _skill = skill;
    _time  = time;

    // Custom starting FEN (puzzles, saved game)
    UCI::init(_pos, _states, customFEN);
    std::cout << "Stockfish position init (FEN) skill=" << skill
              << " time=" << time << " fen=" << (customFEN ? customFEN : "NULL") << "\n";
}

- (void)setPosition:(const char*)fen
{
    UCI::set_position(_pos, _states, fen);
}

- (void)callMove:(int)from :(int)to
{
    UCI::init_move(from, to, _pos, _moveHistory);
}

- (void)castleMove:(int)castleSide
{
    UCI::castle_move(castleSide, _pos, _moveHistory);
}

- (void)enpassantMove:(int)from
{
    UCI::enpassant_move(from, _pos, _moveHistory);
}

- (void)promotionMove:(int)from :(int)to :(int)promoType
{
    UCI::promotion_move(from, to, promoType, _pos, _moveHistory);
}

- (int)searchMove
{
    // For now we just reuse the existing think wrapper.
    // If you want difficulty to really matter, you can
    // modify UCI::think to accept limits based on _skill/_time.
    Move m = UCI::think(_pos, _moveHistory);
    return (int)m;
}

- (void)undoMove
{
    UCI::undo_move(_pos, _moveHistory);
}

- (void)newGame
{
    UCI::new_game(_pos, _states, _moveHistory);
}

- (bool)drawCheck
{
    return UCI::is_game_draw(_pos);
}

- (void)releaseResource
{
    // Currently just releases resources related to _pos.
    // We deliberately DO NOT tear down Threads or global init
    // because Stockfish is not designed for repeated full teardown.
    UCI::release_resources(_pos);
    std::cout << "Stockfish position resources released\n";
}

@end

extern "C"
{
    static StockfishLib *ai = nil;

    static StockfishLib* get_ai()
    {
        if (!ai)
            ai = [[StockfishLib alloc] init];
        return ai;
    }

    void cpp_init_stockfish(double skill, double time)
    {
        [get_ai() init:skill :time];
    }

    void cpp_init_custom_stockfish(double skill, double time, const char* customFEN)
    {
        [get_ai() init:skill :time :customFEN];
    }

    void cpp_set_position(const char* fen)
    {
        [get_ai() setPosition:fen];
    }

    void cpp_call_move(int from, int to)
    {
        [get_ai() callMove:from :to];
    }

    void cpp_castle_move(int castleSide)
    {
        [get_ai() castleMove:castleSide];
    }

    void cpp_enpassant_move(int from)
    {
        [get_ai() enpassantMove:from];
    }

    void cpp_promotion_move(int from, int to, int promoType)
    {
        [get_ai() promotionMove:from :to :promoType];
    }

    int cpp_search_move()
    {
        return [get_ai() searchMove];
    }

    void cpp_undo_move()
    {
        [get_ai() undoMove];
    }

    void cpp_new_game()
    {
        [get_ai() newGame];
    }

    bool cpp_draw_check()
    {
        return [get_ai() drawCheck];
    }

    void cpp_release_resource()
    {
        if (!ai) return;
        [ai releaseResource];
    }

    void cpp_dealloc_stockfish()
    {
        if (!ai) return;
        [ai releaseResource];  // position-level cleanup
        ai = nil;              // drop wrapper; engine globals stay initialized
    }
}