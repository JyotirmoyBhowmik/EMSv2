using Npgsql;
using System.Text.Json;

if (args.Length == 0)
{
    Console.WriteLine(
        JsonSerializer.Serialize(new {
            success = false,
            error = "Config path not provided"
        })
    );
    Environment.Exit(1);
}

var json = File.ReadAllText(args[0]);
var db = JsonDocument.Parse(json)
                     .RootElement
                     .GetProperty("Database");

var csb = new NpgsqlConnectionStringBuilder {
    Host                   = db.GetProperty("Host").GetString(),
    Port                   = db.GetProperty("Port").GetInt32(),
    Database               = db.GetProperty("DatabaseName").GetString(),
    Username               = db.GetProperty("Username").GetString(),
    Password               = Environment.GetEnvironmentVariable("EMS_DB_PASSWORD")
                             ?? throw new InvalidOperationException("EMS_DB_PASSWORD not set"),
    SslMode                = SslMode.Require,
    TrustServerCertificate = false,
    ApplicationName        = "EMSv2.DbClient"
};

try
{
    using var conn = new NpgsqlConnection(csb.ConnectionString);
    await conn.OpenAsync();

    Console.WriteLine(
        JsonSerializer.Serialize(new {
            success = true,
            message = "CONNECTED",
            database = db.GetProperty("DatabaseName").GetString()
        })
    );
}
catch (Exception ex)
{
    Console.WriteLine(
        JsonSerializer.Serialize(new {
            success = false,
            error = ex.Message
        })
    );
    Environment.Exit(1);
}