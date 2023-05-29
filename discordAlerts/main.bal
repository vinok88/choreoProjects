import ballerina/io;
import ballerina/http;
import ballerina/time;
import ballerina/log;
import ballerina/lang.runtime;
import ballerinax/googleapis.gmail as gmail;

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


type newMessage record {|
    json message;
    int alertLevel;
|};

gmail:ConnectionConfig gmailConfig = {
    auth: {
        refreshUrl: gmail:REFRESH_URL,
        refreshToken: googleRefreshToken,
        clientId: googleClientId,
        clientSecret: googleClientSecret
    }
};

http:Client clientEndpoint = check new(discordAPIUrl);
http:Client webhookClient = check new(googleChatAPIUrl);
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
    string requestPath = "/channels/" + channelId + "/messages";
    if latestMessageId.length() > 0 {
        log:printInfo("Starting checking messages after messageID: " + latestMessageId);
        requestPath = requestPath + "?after=" + latestMessageId;
    } else {
        log:printInfo("Starting checking latest messages.");
    }

    json|error response = check clientEndpoint->get(requestPath, headers);

    if (response is error) {
        log:printError("Error getting Discord messages", response);
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
            _ = check sendMail(getEmailMessage(content, author, delaySeconds, id),id);
            item.alertLevel = 3;
            noreplyList[check item.message.id] = item;
        } else if (alert1*60*60 <= delaySeconds) && (item.alertLevel == 1) {
            _ = check sendChatMessage(getMessage(content, author, delaySeconds, id), alertsChatWebhookId);
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
    log:printDebug(message);
    return message;
}

function getEmailMessage(string content, string author, int delay, string messageId) returns string {
    string url = discordWebUrl + "/" + serverId + "/" + channelId + "/" + messageId;
    string msg = content;
    if content.length() > 100 {
        msg = content.substring(0, 100);
    }
    return "Following message on discord channel is not answered for over " + (delay/60/60).toString() 
        + " hours." + "\n" + "Author: " + author +"\n" + "Link: " + url + "\n" + "Message: " + msg; 
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
    string subject = "Escalation alert for un-answered discord message id: " + messageId;
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