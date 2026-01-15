#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <SPIFFS.h>

const char* ssid = "ESP32-haros";
const char* password = "12345678";

AsyncWebServer server(80);

// Pin del LED integrado
const int ledPin = 8;

// Estado y log del LED
bool ledState = false;
String ledLog = "";

// Función que ejecuta un archivo .bas y devuelve HTML
String ejecutarBas(String fname, String ledParam){
    // Ejecutar LED según parámetro GET
    if(ledParam=="ON"){ 
        digitalWrite(ledPin, LOW); 
        ledState=true; 
        ledLog += "LED ENCENDIDO - "+String(millis()/1000)+" s<br>"; 
    }
    if(ledParam=="OFF"){ 
        digitalWrite(ledPin,HIGH); 
        ledState=false; 
        ledLog += "LED APAGADO - "+String(millis()/1000)+" s<br>"; 
    }

    String html = "<!DOCTYPE html><html><head><meta charset='UTF-8'><title>"+fname+"</title></head><body>";

    File f = SPIFFS.open("/"+fname, FILE_READ);
    if(f){
        while(f.available()){
            String line = f.readStringUntil('\n');
            line.trim();

            if(line.startsWith("PRINT ")){
                String msg = line.substring(6);
                html += msg + "<br>";
            }

            if(line=="LED ON"){ digitalWrite(ledPin, LOW); ledState=true; ledLog += "LED ENCENDIDO - "+String(millis()/1000)+" s<br>"; html += "<p>LED ENCENDIDO</p>"; }
            if(line=="LED OFF"){ digitalWrite(ledPin,HIGH); ledState=false; ledLog += "LED APAGADO - "+String(millis()/1000)+" s<br>"; html += "<p>LED APAGADO</p>"; }

            if(line=="STATUS"){
                html += "<p>LED actual: "+String(ledState ? "ENCENDIDO" : "APAGADO")+"</p>";
                html += "<p>Tiempo encendido: "+String(millis()/1000)+" s</p>";
                html += "<p>Memoria libre: "+String(ESP.getFreeHeap())+" bytes</p>";
            }

            if(line=="SHOW_LOG"){
                html += "<h3>Historial de acciones</h3><pre>"+ledLog+"</pre>";
            }
        }
        f.close();
    } else html += "Archivo no encontrado.";

    html += "<p><a href='/'>Volver</a></body></html>";
    return html;
}

void setup() {
    Serial.begin(115200);
    pinMode(ledPin, OUTPUT);
    digitalWrite(ledPin, HIGH); // LED apagado

    if(!SPIFFS.begin(true)){ 
        Serial.println("Error montando SPIFFS"); 
        return; 
    }

    WiFi.softAP(ssid,password);
    Serial.println(WiFi.softAPIP());

    // ---------------- Mini IDE ----------------
    server.on("/", HTTP_GET, [](AsyncWebServerRequest *request){
        String html = "<h1>Practica 1.2: Caracteristicas de la virtualizacion:</h1><ul>";
        File root = SPIFFS.open("/");
        File file = root.openNextFile();
        while(file){
            String name = file.name();
            html += "<li>" + name +
                    " <a href='/edit?file=" + name + "'>Editar</a>" +
                    " <a href='/delete?file=" + name + "'>Eliminar</a>" +
                    " <a href='/" + name.substring(0,name.length()-4) + "'>Ejecutar</a></li>"; // botón ejecutar
            file = root.openNextFile();
        }
        html += "</ul>";
        html += "<h3>Crear nuevo archivo</h3>";
        html += "<form action='/create'><input name='filename' placeholder='nombre.bas'><input type='submit' value='Crear'></form>";
        request->send(200,"text/html",html);
    });

    server.on("/create", HTTP_GET, [](AsyncWebServerRequest *request){
        if(request->hasParam("filename")){
            String fname = request->getParam("filename")->value();
            if(!fname.endsWith(".bas")) fname += ".bas";
            File f = SPIFFS.open("/"+fname, FILE_WRITE);
            if(f){ f.println("PRINT \"Hola Mundo\""); f.close(); }
        }
        request->redirect("/");
    });

    server.on("/edit", HTTP_GET, [](AsyncWebServerRequest *request){
        if(!request->hasParam("file")) { request->redirect("/"); return; }
        String fname = request->getParam("file")->value();
        String html = "<h2>Editar: "+fname+"</h2><form method='POST' action='/save?file="+fname+"'>";
        File f = SPIFFS.open("/"+fname, FILE_READ);
        String content=""; if(f){ content=f.readString(); f.close(); }
        html += "<textarea name='code' style='width:100%;height:300px;'>"+content+"</textarea><br>";
        html += "<input type='submit' value='Guardar'></form><p><a href='/'>Volver</a></p>";
        request->send(200,"text/html",html);
    });

    server.on("/save", HTTP_POST, [](AsyncWebServerRequest *request){
        if(request->hasParam("file") && request->hasParam("code",true)){
            String fname = request->getParam("file")->value();
            String code = request->getParam("code",true)->value();
            File f = SPIFFS.open("/"+fname, FILE_WRITE); if(f){ f.print(code); f.close(); }
        }
        request->redirect("/");
    });

    server.on("/delete", HTTP_GET, [](AsyncWebServerRequest *request){
        if(request->hasParam("file")){
            String fname = request->getParam("file")->value();
            SPIFFS.remove("/" + fname);
        }
        request->redirect("/");
    });

    // ---------------- Rutas fijas (opcional) ----------------
    server.on("/control", HTTP_GET, [](AsyncWebServerRequest *request){
        String ledParam = request->hasParam("led") ? request->getParam("led")->value() : "";
        request->send(200,"text/html", ejecutarBas("control.bas", ledParam));
    });
    server.on("/status", HTTP_GET, [](AsyncWebServerRequest *request){
        request->send(200,"text/html", ejecutarBas("status.bas", ""));
    });
    server.on("/log", HTTP_GET, [](AsyncWebServerRequest *request){
        request->send(200,"text/html", ejecutarBas("log.bas", ""));
    });

    // ---------------- Rutas dinámicas para cualquier .bas ----------------
    server.onNotFound([](AsyncWebServerRequest *request){
        String path = request->url();
        if(path.startsWith("/")) path = path.substring(1);
        String fname = path + ".bas";
        if(SPIFFS.exists("/" + fname)){
            String ledParam = request->hasParam("led") ? request->getParam("led")->value() : "";
            request->send(200,"text/html", ejecutarBas(fname, ledParam));
        } else {
            request->send(404,"text/plain","Archivo no encontrado.");
        }
    });

    server.begin();
}

void loop() {}
