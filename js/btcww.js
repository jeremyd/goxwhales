
// simpleSockets block ?
//var SocketKlass = "MozWebSocket" in window ? MozWebSocket : WebSocket;
//var ws = new SocketKlass('ws://' + window.location.host + '/timeinfo');

// ReconnectingWebSocket.debugAll = true;
var ws = new ReconnectingWebSocket('ws://' + window.location.host + '/timeinfo');

//ws.onclose = function(e) {
//
//}
//ws.onerror = function(e) {
//
//}

var canvas = document.getElementById('cells');
var ctx = canvas.getContext("2d");
var counter = 150;
var x = 0;
var y = 0;
var xx = 0;
var yy = 0;
var world_hash = {};
var nodes = []
var animations = [];
var messages = [];
var wactive = [];
var selected = [];
var updown = 0;

var tuximg1 = new Image();
tuximg1.src = "http://s3.amazonaws.com/goxwhales/static_assets/sprites/melwe_whale.png";

//var tuximg2 = new Image();
//tuximg2.src = "http://s3.amazonaws.com/goxwhales/static_assets/sprites/whale-love.png";

var mySound = new buzz.sound( "http://s3.amazonaws.com/goxwhales/static_assets/audio/sensrnet", {
    formats: [ "ogg" ] //, "mp3", "acc" ]
});

function drawTux1(tx, ty) {
  ctx.drawImage(tuximg1, tx, ty)
}

//function drawTux2(tx, ty) {
//  ctx.drawImage(tuximg2, tx, ty)
//}

function drawText(text, dx, dy, max) {
  //clear the text..
  ctx.clearRect(dx,dy-20,max,40);

  //draw the text..
  ctx.fillStyle = "rgb(250,250,250)";
  ctx.font = "20pt Helvetica";
  ctx.fillText(text, dx, dy, max);
}

function clearText(text, dx, dy) {
  ctx.fillStyle = "rgb(200,200,200)";
  ctx.font = "12pt Helvetica";
  ctx.fillText(text, dx, dy);
}

function animate() {
  if(updown == 0) {
    counter = counter + 10; 
  }
  else {
    counter = counter - 10;
  }
  if(counter > 200) { updown = 1 }
  if(counter < 150) { updown = 0 }
  ctx.fillStyle = "rgb(0," + counter + ",0)";
  //ctx.fillStyle = "rgb(0,100,0)";
  ctx.strokeStyle = "#0f0";
  for(var i = 0; i < nodes.length; i++) {
    if(selected[i] == true) {
      ctx.fillStyle = "rgb(180,0,200)";
    }
    else if(nodes[i]["state"] == "low") {
      ctx.fillStyle = "rgb(0," + counter + ",0)";
    }
    else {
      ctx.fillStyle = "rgb(200,0,0)";
    }
    x = nodes[i]["x"];
    y = nodes[i]["y"];
    xx = nodes[i]["xx"];
    yy = nodes[i]["yy"];
    //console.log(x, y, xx, yy);

    // clear the maximum height rect
    ctx.clearRect(x,y,xx,1080);

    // draw the rect
    ctx.fillRect(x,y,xx,yy);

    drawText(nodes[i]["id"], x, y, xx);
    if((i % 2) == 0) {
      drawTux1((x-50),y);
    }
    else {
      drawTux1((x-50),y);
    }

  }
}

function hilight(xcoord,ycoord) {
  var foundx = false;
  var foundy = false;
  xcoord = xcoord - 480;
  ycoord = ycoord - 435;
  for(var i = 0; i < nodes.length; i++) {
    if((xcoord >= nodes[i]["x"]) && (xcoord <= nodes[i]["xx"])) { foundx = true; }
    if((ycoord >= nodes[i]["x"]) && (ycoord <= nodes[i]["yy"])) { foundy = true; }   
    if(foundx && foundy && selected[i] == true) {
      selected[i] = false;
      console.log(foundx,foundy);
      return true;
    } else if(foundx && foundy) {
      selected[i] = true;
      console.log(foundx,foundy);
      return true;
    } 
  }
}

drawText("ticker -/+ 10 USD:", 10, 100, 200);
drawText("Please wait.  Waiting for event..", 10 , 19, canvas.width);

canvas.addEventListener('mousedown', function(e) {
  var mx = e.pageX;
  var my = e.pageY;
  console.log(mx, my);
  hilight(mx, my);
})

ws.onmessage = function(msg){
  world_hash = JSON.parse(msg.data);
  nodes = world_hash["nodes"];
  messages = world_hash["messages"];
  //wactivity = world_hash["wactivity"];
  if(world_hash["messages"]) {
    //$("#logs").html("<code>" + world_hash["messages"].join("<br>"));
    $("#logs").html("<code>" + world_hash["messages"].join("<br>") + "</code>");
  }
  if(world_hash["sightings"]) {
    $("#sightings").html("<code>" + world_hash["sightings"].join("<br>"));
  }
  // play alert sound
  if (world_hash["alert"] == "true") {
    mySound.play()
      .fadeIn();
      //.bind( "timeupdate", function() {
          //var timer = buzz.toTimer( this.getTime() );
          //document.getElementById( "timer" ).innerHTML = timer;
      //});
  }

  // stop the previous animations
  //for(var j = 0; j < animations.length; j++) {
  //  var kill_this = animations.pop();
  //  clearInterval(kill_this);
  //}

  // clear the drawing board
  // kinda slow and flickery to clear the whole board..
  //ctx.clearRect(0, 0, canvas.width, canvas.height);
  // start new animations
  //for(var i = 0; i < nodes.length; i++) {
    // store the animation ids
  //  animations.push(setInterval(animate, 10000));
  //}

  //if( !animations[0] ) {
  //  animations.push(setInterval(animate, 500));
  //}
  animate();

  drawText(world_hash["ticker"], 10, 20, canvas.width);
  drawText(world_hash["last_alert"], 10, 60, canvas.width);
}
