public interface IFrogChessHub
{
    Task JoinOrCreateGame(string gameId, string playerName);
    Task MakeMove(string gameId, int fromRow, int fromCol, int toRow, int toCol);
    Task LeaveGame(string gameId);
}

public interface IFrogChessClient
{
    Task MoveMade(GameStateDto gameState);
    Task GameStarted(GameStateDto gameState);
    Task GameFinished(GameStateDto gameState);
    Task PlayerJoined(string[] players);
    Task Error(string message);
}

public class GameStateDto
{
    public Guid GameId { get; set; }
    public string[][] Board { get; set; }
    public int CurrentPlayer { get; set; }
    public string[] Players { get; set; }
    public bool IsGameOver { get; set; }
    public int? Winner { get; set; }
}