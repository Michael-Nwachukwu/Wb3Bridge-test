// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

contract Ludo {
    uint256 gameId;
    uint256 nonce = 0;
    uint256 boardNumber = 52;
    // Ludo board has 52 positions
    uint[52] public ludoBoard;


    struct Game {
        uint256 id;
        uint8 numberOfPlayers;
        string[] colors;
        address[] players;
        uint8 nextColorindex;
    }

    struct Player {
        string color;
        bool isActive;
        bool isTurn;
        uint position;
        address player;
    }

    mapping (address => Player) players;
    mapping (uint256 => Game) games;
    mapping (address => mapping (uint256 => bool)) hasJoinedGame;


    function createGame(string[] memory _colors) external {

        uint256 _gameId = gameId + 1;    
        Game storage newGame = games[_gameId];

        newGame.id = _gameId;
        newGame.colors = _colors;

    }

    function joinGame(uint256 _gameId) external {
        require(!hasJoinedGame[msg.sender][_gameId], "Already joined");
        Game storage game = games[_gameId];
        require(game.nextColorindex < game.colors.length, "Game is full");

        Player storage newPlayer = players[msg.sender];
        newPlayer.color = game.colors[game.nextColorindex];
        newPlayer.player = msg.sender;
        newPlayer.position = ludoBoard[0];

        game.players.push(msg.sender);
        game.nextColorindex++;
        game.numberOfPlayers++;

        hasJoinedGame[msg.sender][_gameId] = true;
    }

    function rollDice(address player) internal returns (uint8) {

        uint256 result = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            player,
            nonce
        )));
        nonce++;
        return uint8(result % 6) + 1;

    }

    function play(uint256 _gameId) external {

        require(hasJoinedGame[msg.sender][_gameId], "Player not in game");

        Game storage game = games[_gameId];
        Player storage player = players[msg.sender];

        uint8 moves = rollDice(msg.sender);

        player.position = ludoBoard[moves];

    }




}