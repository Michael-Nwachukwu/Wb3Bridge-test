// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Ludo Game Smart Contract
 * @author [Your Name]
 * @notice This contract implements a blockchain version of the classic Ludo board game
 * @dev The game uses pseudorandom number generation for dice rolls and handles multiple concurrent games
 */
contract Ludo {
    /**
     * @dev Game board constants
     */
    uint256 public constant BOARD_SIZE = 52;
    uint256 public constant MAX_PLAYERS = 4;
    uint256 public constant HOME_DISTANCE = 6;
    
    /**
     * @dev Game state variables
     */
    uint256 public gameId;
    uint256 private nonce;
    
    /**
     * @dev Events for game actions
     */
    event GameCreated(uint256 indexed gameId, address creator);
    event PlayerJoined(uint256 indexed gameId, address player, string color);
    event DiceRolled(uint256 indexed gameId, address player, uint8 roll);
    event PieceMoved(uint256 indexed gameId, address player, uint256 fromPosition, uint256 toPosition);
    event GameWon(uint256 indexed gameId, address winner);

    /**
     * @dev Game struct to store game-specific data
     */
    struct Game {
        uint256 id;
        uint8 numberOfPlayers;
        string[] colors;
        address[MAX_PLAYERS] players;
        uint8 nextColorIndex;
        uint8 currentTurn;
        bool isActive;
        address winner;
    }

    /**
     * @dev Player struct to store player-specific data
     */
    struct Player {
        string color;
        bool isActive;
        bool[] piecesAtHome;
        uint256[] piecePositions;
        uint256 finishedPieces;
        address playerAddress;
    }

    /**
     * @dev Mappings to store game and player data
     */
    mapping(uint256 => Game) public games;
    mapping(uint256 => mapping(address => Player)) public gamePlayers;
    mapping(address => mapping(uint256 => bool)) public hasJoinedGame;

    /**
     * @notice Creates a new Ludo game
     * @param _colors Array of colors for the game (should match number of players)
     * @return gameId The ID of the newly created game
     */
    function createGame(string[] memory _colors) external returns (uint256) {
        require(_colors.length <= MAX_PLAYERS, "Too many colors");
        
        gameId++;
        Game storage newGame = games[gameId];
        
        newGame.id = gameId;
        newGame.colors = _colors;
        newGame.isActive = true;
        
        emit GameCreated(gameId, msg.sender);
        return gameId;
    }

    /**
     * @notice Allows a player to join an existing game
     * @param _gameId The ID of the game to join
     */
    function joinGame(uint256 _gameId) external {
        require(!hasJoinedGame[msg.sender][_gameId], "Already joined");
        
        Game storage game = games[_gameId];
        require(game.isActive, "Game not active");
        require(game.nextColorIndex < game.colors.length, "Game is full");

        Player storage newPlayer = gamePlayers[_gameId][msg.sender];
        newPlayer.color = game.colors[game.nextColorIndex];
        newPlayer.playerAddress = msg.sender;
        newPlayer.isActive = true;
        newPlayer.piecesAtHome = new bool[](4);
        newPlayer.piecePositions = new uint256[](4);
        
        // Initialize pieces at home
        for (uint256 i = 0; i < 4; i++) {
            newPlayer.piecesAtHome[i] = true;
        }

        game.players[game.nextColorIndex] = msg.sender;
        game.nextColorIndex++;
        game.numberOfPlayers++;

        hasJoinedGame[msg.sender][_gameId] = true;
        
        emit PlayerJoined(_gameId, msg.sender, newPlayer.color);
    }

    /**
     * @dev Internal function to generate a pseudo-random dice roll
     * @return A number between 1 and 6
     */
    function rollDice() internal returns (uint8) {
        uint256 result = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            msg.sender,
            nonce
        )));
        nonce++;
        uint8 roll = uint8(result % 6) + 1;
        return roll;
    }

    /**
     * @notice Allows a player to take their turn
     * @param _gameId The game ID
     * @param _pieceIndex The index of the piece to move (0-3)
     */
    function playTurn(uint256 _gameId, uint8 _pieceIndex) external {
        require(hasJoinedGame[msg.sender][_gameId], "Not in game");
        require(_pieceIndex < 4, "Invalid piece index");
        
        Game storage game = games[_gameId];
        Player storage player = gamePlayers[_gameId][msg.sender];
        
        require(game.isActive, "Game not active");
        require(game.players[game.currentTurn] == msg.sender, "Not your turn");
        
        uint8 diceRoll = rollDice();
        emit DiceRolled(_gameId, msg.sender, diceRoll);
        
        // Handle piece movement
        if (player.piecesAtHome[_pieceIndex]) {
            if (diceRoll == 6) {
                _movePieceOutOfHome(_gameId, player, _pieceIndex);
            }
        } else {
            _movePiece(_gameId, player, _pieceIndex, diceRoll);
        }
        
        // Check for win condition
        if (player.finishedPieces == 4) {
            game.isActive = false;
            game.winner = msg.sender;
            emit GameWon(_gameId, msg.sender);
        }
        
        // Move to next player's turn if roll wasn't 6
        if (diceRoll != 6) {
            game.currentTurn = (game.currentTurn + 1) % game.numberOfPlayers;
        }
    }

    /**
     * @dev Internal function to move a piece out of home
     * @param _gameId The game ID
     * @param player The player struct
     * @param _pieceIndex The index of the piece to move
     */
    function _movePieceOutOfHome(uint256 _gameId, Player storage player, uint8 _pieceIndex) internal {
        player.piecesAtHome[_pieceIndex] = false;
        uint256 startPosition = _getStartPosition(_gameId, msg.sender);
        player.piecePositions[_pieceIndex] = startPosition;
        
        emit PieceMoved(_gameId, msg.sender, 0, startPosition);
    }

    /**
     * @dev Internal function to move a piece on the board
     * @param _gameId The game ID
     * @param player The player struct
     * @param _pieceIndex The index of the piece to move
     * @param _spaces Number of spaces to move
     */
    function _movePiece(
        uint256 _gameId,
        Player storage player,
        uint8 _pieceIndex,
        uint8 _spaces
    ) internal {
        uint256 currentPos = player.piecePositions[_pieceIndex];
        uint256 newPos = (currentPos + _spaces) % BOARD_SIZE;
        
        // Check if piece has completed a full circle and is entering home stretch
        uint256 startPos = _getStartPosition(_gameId, msg.sender);
        if (currentPos < startPos && newPos >= startPos && newPos < startPos + HOME_DISTANCE) {
            player.finishedPieces++;
            player.piecePositions[_pieceIndex] = type(uint256).max; // Mark as finished
        } else {
            player.piecePositions[_pieceIndex] = newPos;
            _checkCapture(_gameId, msg.sender, newPos);
        }
        
        emit PieceMoved(_gameId, msg.sender, currentPos, newPos);
    }

    /**
     * @dev Internal function to check if a piece can capture another piece
     * @param _gameId The game ID
     * @param _player The player's address
     * @param _position The position to check for capture
     */
    function _checkCapture(uint256 _gameId, address _player, uint256 _position) internal {
        Game storage game = games[_gameId];
        
        for (uint8 i = 0; i < game.numberOfPlayers; i++) {
            address otherPlayer = game.players[i];
            if (otherPlayer != _player) {
                Player storage opponent = gamePlayers[_gameId][otherPlayer];
                for (uint8 j = 0; j < 4; j++) {
                    if (!opponent.piecesAtHome[j] && opponent.piecePositions[j] == _position) {
                        opponent.piecesAtHome[j] = true;
                        opponent.piecePositions[j] = 0;
                        emit PieceMoved(_gameId, otherPlayer, _position, 0);
                    }
                }
            }
        }
    }

    /**
     * @dev Internal function to calculate the starting position for a player
     * @param _gameId The game ID
     * @param _player The player's address
     * @return The starting position on the board
     */
    function _getStartPosition(uint256 _gameId, address _player) internal view returns (uint256) {
        Game storage game = games[_gameId];
        for (uint8 i = 0; i < game.numberOfPlayers; i++) {
            if (game.players[i] == _player) {
                return i * (BOARD_SIZE / MAX_PLAYERS);
            }
        }
        revert("Player not found");
    }

    /**
     * @notice Returns the current state of a game
     * @param _gameId The game ID
     * @return numberOfPlayers The number of players in the game
     * @return currentTurn The index of the current player's turn
     * @return isActive Whether the game is still active
     * @return winner The address of the winner (if game is finished)
     */
    function getGameState(uint256 _gameId) external view returns (
        uint8 numberOfPlayers,
        uint8 currentTurn,
        bool isActive,
        address winner
    ) {
        Game storage game = games[_gameId];
        return (
            game.numberOfPlayers,
            game.currentTurn,
            game.isActive,
            game.winner
        );
    }

    /**
     * @notice Returns the current state of a player in a game
     * @param _gameId The game ID
     * @param _player The player's address
     * @return color The player's color
     * @return isActive Whether the player is active
     * @return piecePositions Array of positions for each piece
     * @return finishedPieces Number of pieces that have finished
     */
    function getPlayerState(uint256 _gameId, address _player) external view returns (
        string memory color,
        bool isActive,
        uint256[] memory piecePositions,
        uint256 finishedPieces
    ) {
        Player storage player = gamePlayers[_gameId][_player];
        return (
            player.color,
            player.isActive,
            player.piecePositions,
            player.finishedPieces
        );
    }
}