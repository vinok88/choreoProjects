import ballerina/io;
import ballerina/http;
import ballerina/time;
import ballerina/log;
import ballerina/lang.runtime;
import ballerinax/googleapis.gmail as gmail;

configurable string botToken = ?;
configurable int alert1 = 6;
configurable int alert2 = 16;
configurable int alert3 = 20;
configurable int frequency = 3;
configurable int contentLength = 40;
configurable string alertsChatWebhookId = "/spaces/AAAA2chLzm0/messages?key=AIzaSyDdI0hCZtE6vySjMm-WEfRq3CPzqKqqsHI&token=femuOHTxiMVO1nPba0TcYqRaGjlNLJfeyqlQZBWaa94";
configurable string escalationChatWebhookId = "/spaces/AAAApTEeg10/messages?key=AIzaSyDdI0hCZtE6vySjMm-WEfRq3CPzqKqqsHI&token=NXry6cuwXhZvWOzV1BWrgQN7G4snDFDPH8pDHMy-1Jc";
configurable string serverId = "1108977085948637277";
configurable string channelId = "1108977086674256026";
configurable string discordWebUrl = "https://discord.com/channels";
configurable string gmailRefreshToken = ?;
configurable string gmailClientId = ?;
configurable string gmailClientSecret = ?;
configurable string gmailReceipent = ?;
configurable string gmailSender = ?;

type newMessage record {|
    json message;
    int alertLevel;
|};

gmail:ConnectionConfig gmailConfig = {
    auth: {
        refreshUrl: gmail:REFRESH_URL,
        refreshToken: gmailRefreshToken,
        clientId: gmailClientId,
        clientSecret: gmailClientSecret
    }
};

http:Client clientEndpoint = check new("https://discord.com/api");
http:Client webhookClient = check new("https://chat.googleapis.com/v1");
gmail:Client gmailClient = check new (gmailConfig);
map<newMessage> noreplyList = {};
string latestMessageId = "";


public function main() returns error? {
    boolean continueLoop = true;
    while continueLoop {
        error? result = sendAlerts();
        if result is error {
            continueLoop = false;
            log:printError("Error: ", result);
            log:printInfo("Terminating Discord Alert program.");
        }
        runtime:sleep(frequency*60);
    }
    
}

function sendAlerts() returns error? {
    map<string> headers = {};
    headers["Authorization"] =  "Bot " + botToken;
    string requestPath = "/channels/1108977086674256026/messages";
    if latestMessageId.length() > 0 {
        log:printInfo("Starting checking messages after messageID: " + latestMessageId);
        requestPath = requestPath + "?after=" + latestMessageId;
    }

    json|error response = check clientEndpoint->get(requestPath, headers);

    if (response is error) {
        io:println(response.message());
        return;
    }
    
    if response is json[] {
        // Assumption : Latest message is sent first in the response array
        if response.length() > 0 {
            latestMessageId = check response[0].id;
        }
        
        int i = 0;
        while i < response.length() {
            // need to start with the oldest message, hence popping from the end
            json message = response.pop();
            string? referance = check message?.referenced_message?.id;
            // int? position = check message?.position;
            if !(referance is string) {
                // this is a first message, add to list
                noreplyList[check message.id] = {message: message, alertLevel: 1};
            } else {
                // we have a referance, check if this is a reply to one of new messages
                if (noreplyList.hasKey(referance)) {
                    // this is a reply to a new message
                    _ = noreplyList.remove(referance);
                    io:println("Removed reply: " , referance , " : " , check message.content);
                }
            }
        }
    }

    time:Utc now = time:utcNow();
    // now send notification for each item in the list
    foreach json item in noreplyList  {
        string content = check item.message.content;
        string author = check item.message.author?.username;
        string timestamp = check item.message.timestamp;
        string id = check item.message.id;
        time:Utc sentTime = check time:utcFromString(timestamp);
        int delaySeconds = now[0] - sentTime[0];
        if (alert3*60*60 <= delaySeconds) && (item.alertLevel == 3) {
            _ = check sendChatMessage(getMessage(content, author, delaySeconds, id), escalationChatWebhookId);
            // we are not going to send alerts for this message anymore
            io:println("Alert 3: " , author , " sent a message " , delaySeconds/60/60 , " hours ago");
            _ = noreplyList.remove(check item.message.id);
        } else if (alert2*60*60 <= delaySeconds) && (item.alertLevel == 2) {
            io:println("Alert 2: " , author , " sent a message " , delaySeconds/60/60 , " hours ago");
            _ = check sendMail(getMessage(content, author, delaySeconds, id),id);
            item.alertLevel = 3;
            noreplyList[check item.message.id] = item;
        } else if (alert1*60*60 <= delaySeconds) && (item.alertLevel == 1) {
            _ = check sendChatMessage(getMessage(content, author, delaySeconds, id), escalationChatWebhookId);
            item.alertLevel = 2;
            noreplyList[check item.message.id] = item;
        }
    }
}

function getMessage(string content, string author, int delay, string messageId) returns string {
    int length = contentLength;
    if (content.length() < length) {
        length = content.length();
    }
    string url = discordWebUrl + "/" + serverId + "/" + channelId + "/" + messageId;
    string message = "New message: " + content + "..., by: " + author + ", not answered for: " + (delay/60/60).toString() + " hours." + " Link: " + url;
    log:printInfo(message);
    return message;
}


function sendChatMessage(string message, string spaceId) returns error? {
    map<string> headers = {};
    headers["Content-Type"] = "application/json";
    json payload = {text: message};
    http:Response|error response = check webhookClient->post(spaceId, payload, headers);
    if (response is error) {
        log:printError("Error sending message to chat space: ", response);
        return response;
    } 
    
    return;
}

function sendMail(string message, string messageId) returns error? {
    string subject = "Escalation alert for discord message id: " + messageId;
    gmail:MessageRequest messageRequest = {
        recipient : gmailReceipent,
        sender : gmailSender,
        // cc : "cc@gmail.com",
        subject : subject,
        messageBody : message,
        contentType : gmail:TEXT_PLAIN
    };
    gmail:Message|error response = gmailClient->sendMessage(messageRequest);

    if response is error {
        log:printError("Error sending email: ", response);
        return response;
    }
}