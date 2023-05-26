import ballerina/io;
import ballerina/http;
import ballerina/time;
import ballerina/log;
import ballerina/lang.runtime;

configurable string botToken = ?;
configurable int alert1 = 1;
configurable int alert2 = 16;
configurable int alert3 = 200;
configurable int frequency = 1;
string latestMessageId = "";

type newMessage record {|
    json message;
    int alertLevel;
|};

http:Client clientEndpoint = check new("https://discord.com/api");
map<newMessage> noreplyList = {};

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
        io:println("lastMessageID:", latestMessageId);
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
                io:println("Added new message: " , check message.id , " : " , check message.content);
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
        // "timestamp":"2023-05-23T04:06:29.385000+00:00"
        // time:Time parsedTime = check time:parse("2021-02-28T23:10:15.02+05:30[Asia/Colombo]", time:ISO_8601);
        time:Utc sentTime = check time:utcFromString(timestamp);
        int delaySeconds = now[0] - sentTime[0];
        if (alert3*60*60 <= delaySeconds) && (item.alertLevel == 3) {
            io:println("Alert 3: " , author , " sent a message " , delaySeconds/60/60 , " hours ago");
            // we are not going to send alerts for this message anymore
            _ = noreplyList.remove(check item.message.id);
        } else if (alert2*60*60 <= delaySeconds) && (item.alertLevel == 2) {
            io:println("Alert 2: " , author , " sent a message " , delaySeconds/60/60 , " hours ago");
            item.alertLevel = 3;
            noreplyList[check item.message.id] = item;
        } else if (alert1*60*60 <= delaySeconds) && (item.alertLevel == 1) {
            io:println("Alert 1: " , author , " sent a message " , delaySeconds/60/60 , " hours ago");
            item.alertLevel = 2;
            noreplyList[check item.message.id] = item;
        }
    }
}

