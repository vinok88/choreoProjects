import ballerina/http;
import ballerina/log;
import ballerina/lang.runtime;

configurable int alert1 = 6;
configurable int alert2 = 16;
configurable int alert3 = 20;
configurable int frequency = 15;
configurable int contentLength = 40;
configurable string botToken = ?;
configurable string serverId = ?;
configurable string channelId = ?;
configurable string discordWebUrl = "https://discord.com/channels";
configurable string discordAPIUrl = "https://discord.com/api";
configurable string alertsChatWebhookId = ?;
configurable string escalationChatWebhookId = ?;
configurable string googleRefreshToken = ?;
configurable string googleClientId = ?;
configurable string googleClientSecret = ?;
configurable string gmailReceipent = ?;
configurable string gmailSender = ?;
configurable string googleChatAPIUrl = "https://chat.googleapis.com/v1";
configurable boolean continueOnError = true;

# A service representing a network-accessible API
# bound to port `9090`.
@display {
	label: "DiscordNotifierService",
	id: "DiscordNotifierService-03799080-4922-434b-99e9-8684a9d44ac6"
}
service / on new http:Listener(9090) {

    # A resource for generating greetings
    # + name - the input string name
    # + return - string name with hello message or error
    resource function get greeting(string name) returns string|error {
        // Send a response back to the caller.
        if name is "" {
            return error("name should not be empty!");
        }
        return "Hello, " + name;
    }
}

public function main() returns error? {
    while true {
        error? result = sendAlerts();
        if result is error {
            if continueOnError {
                log:printError("Error occurred while sending alerts: " + result.message());
            } else {
                panic result;
            }
        }
        runtime:sleep(frequency*60);
    }

}
