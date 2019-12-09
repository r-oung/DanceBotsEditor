import QtQuick 2.6
import dancebots.backend 1.0

import "../GuiStyle"

Canvas{
  id: root
  height: Style.timerBar.height * appWindow.width

  property color color
  property var occupied: []
  property var keys
  property var model
  property var primitiveColors
  property var primitiveTextIDs
  property alias timeIndicatorPosition: timeIndicator.position
  property var ghosts: []
  property var beats: []
  property var controlBox: null
  property bool isNotEmpty: primitiveView.count > 0
  property bool isMotorBar: false
  property var primitiveY: appWindow.width*Style.timerBar.height * (1.0 - Style.primitives.height)/2

  property real frameToPixels: appWindow.frameToPixels
  property int lengthInFrames: 0

  onFrameToPixelsChanged: width = lengthInFrames * appWindow.frameToPixels
  onLengthInFramesChanged: width = lengthInFrames * appWindow.frameToPixels

  // connect to done loading signal of backend to redraw rectangle
  Connections{
	  target: backend
	  onDoneLoading:{
      if(result){
        // pre-create a few ghosts:
        createGhosts(10);
        // resize rectangle to fit song
        lengthInFrames = backend.getAudioLengthInFrames()
        timeIndicator.visible = true
        beats=backend.getBeats()
        requestPaint();
        // clear occupancy array:
        occupied.length = 0
        for(var i = 0; i < beats.length; ++i){
          occupied.push(false)
        }
      }
    }
  }

  DropArea{
    anchors.fill: parent
    id: dropArea
    keys: parent.keys

    function doDrop(){
      if(drag.source.children[0].isFromBar){
        // source is timerbar itself, just update primitive and
        // set location beats to occupied
        for(var i=0; i < drag.source.children.length; ++i){
          drag.source.children[i].y = root.y
              + primitiveY
          drag.source.children[i].updatePrimitive();
          setOccupied(drag.source.children[i].primitive)
        }
      }else{
        // source is control box, add it to model and destroy delegate
        model.add(drag.source.children[0].primitive)
        drag.source.children[0].destroy()
        // don't have to update occupied as this happens from repeater
        // callback onItemAdded
      }
    }

    function handleInvalidDrop(){
      if(!drag.source.hasChildren){
        return
      }
      // cannot drop
      if(drag.source.children[0].isFromBar){
        // if source is timer bar and items were not copied,
        // do nothing and let it bounce back
        if(drag.source.copy){
          drag.source.deleteAll()
        }else{
          for(var i = 0; i < drag.source.children.length; ++i){
            ghosts[i].visible = false
            drag.source.children[i].updatePrimitive();
            // and reset occupied
            setOccupied(drag.source.children[i].primitive)
          }
        }
      }else{
        // if source is control box, delete the (always single) primitive
        drag.source.children[0].destroy()
      }
    }

    onDropped:{
      beatIndicator.visible = false
      drag.source.reset()
      var currentFrame = drag.x / appWindow.frameToPixels;
      var beatLoc = backend.getBeatAtFrame(currentFrame)
      var positions = []
      var lengths = []
      if(beatLoc >= 0 && drag.source.hasChildren){
        // update ghosts for each child in dragger
        var beatOffset = drag.source.children[0].primitive.positionBeat
        var allValid = true
        for(var i = 0; i < drag.source.children.length; ++i){
          var primitive = drag.source.children[i].primitive
          var startBeat = beatLoc + primitive.positionBeat - beatOffset
          positions.push(startBeat)
          // hide ghosts in any case
          ghosts[i].visible = false
          var validLength = getValidLength(startBeat, primitive.lengthBeat)
          lengths.push(validLength)
          if(validLength <= 0){
            allValid = false
            break
          }
        }
        if(allValid){
          // set all positions and lengths:
          for(var j = 0; j < drag.source.children.length; ++j){
            drag.source.children[j].primitive.positionBeat = positions[j]
            drag.source.children[j].primitive.lengthBeat = lengths[j]
          }
          doDrop()
          return
        }
      }
      handleInvalidDrop()
    }

    onEntered:{
      createGhosts(drag.source.children.length)
      for(var i = 0; i < drag.source.children.length; ++i){
        // set width of ghosts to primitive width:
        ghosts[i].width = drag.source.children[i].width
      }
      beatIndicator.visible = true
    }

    onExited:{
      for(var i = 0; i < drag.source.children.length; ++i){
        ghosts[i].visible = false
      }
      beatIndicator.visible = false
    }

    onPositionChanged:{
      var currentFrame = drag.x / appWindow.frameToPixels;
      var beatLoc = backend.getBeatAtFrame(currentFrame)
      if(beatLoc >= 0){
        // update beat indicator:
        beatIndicator.text = beatLoc
        beatIndicator.x = beats[beatLoc] * appWindow.frameToPixels
        // update ghosts for each child in dragger
        var beatOffset = drag.source.children[0].primitive.positionBeat
        for(var i = 0; i < drag.source.children.length; ++i){
          var primitive = drag.source.children[i].primitive
          var startBeat = beatLoc + primitive.positionBeat - beatOffset
          ghosts[i].visible = true
          ghosts[i].x = beats[startBeat] * appWindow.frameToPixels
          var validLength = getValidLength(startBeat, primitive.lengthBeat)
          if(validLength > 0){
            ghosts[i].isValid = true
            var endPixel = beats[startBeat + validLength] * appWindow.frameToPixels
            ghosts[i].width = endPixel - ghosts[i].x
          }else{
            ghosts[i].isValid = false
          }

          // check if length of drag shape can be corrected:
          var end = primitive.lengthBeat + startBeat
          if(end < beats.length){
            drag.source.children[i].width= (beats[end] - beats[startBeat])
              * appWindow.frameToPixels;
          }
        }
      }
    }
  }

  function getValidLength(start, length){
    var validLength = 0
    var end = start + length;
    if(end > occupied.length - 1){
      end = occupied.length - 1;
    }
    for(var j = start; j < end; ++j){
      if(!occupied[j]){
        ++validLength;
      }else{
        break;
      }
    }
    return validLength;
  }

  Rectangle{
    id: timeIndicator
    color: Style.timerBar.timeBarColor
    width: Style.timerBar.timeBarWidth * root.height
    height: parent.height
    property var position: 0
    x: position - width/2
  }

  Rectangle{
    id: beatIndicator
    color: Style.timerBar.beatIndicatorBgColor
    visible: false
    anchors.bottom: root.isMotorBar ? root.top : undefined
    anchors.top: root.isMotorBar ? undefined : root.bottom
    property var text: "15"
    width: beatText.width
    height: beatText.height
    Text{
      id: beatText
      text: beatIndicator.text
      padding: Style.timerBar.beatIndicatorPadding * root.height
      font.pixelSize: Style.timerBar.beatIndicatorFontSize * root.height
      color: Style.timerBar.beatIndicatorFontColor
    }
  }

  Repeater{
    id: primitiveView
    model: parent.model
    PrimitiveDelegate{
      primitive: model.item
      idleParent: primitiveView
      isFromBar: true
      dragTarget: root.dragTarget
      y: primitiveY
      PrimitiveToolTip{
        isMotor: root.isMotorBar
      }
    }

    onItemRemoved: {
      freeOccupied(item.primitive)
    }

    onItemAdded: {
      setOccupied(item.primitive)
    }

    function duplicateItem(item){
      var prim = controlBox.duplicatePrimitive(item.primitive)
      parent.model.add(prim)
    }
  }

  function setOccupied(primitive){
    var end = primitive.positionBeat + primitive.lengthBeat;
    for(var i = primitive.positionBeat; i < end; ++i){
      occupied[i] = true;
    }
  }

  function freeOccupied(primitive){
    var end = primitive.positionBeat + primitive.lengthBeat;
    for(var i = primitive.positionBeat; i < end; ++i){
      occupied[i] = false;
    }
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.fillStyle = color
    ctx.fillRect(0, 0, width, height)
    for(var i=0; i < beats.length; i++){
      ctx.lineWidth = Style.timerBar.beatWidth * root.height
      ctx.strokeStyle = Style.timerBar.beatColor
      ctx.beginPath()
      var loc = beats[i] * appWindow.frameToPixels
      ctx.moveTo(loc, 0)
      ctx.lineTo(loc, height)
      ctx.stroke()
    }
  }

  function createGhosts(desiredNumber){
    for(var i = ghosts.length; i < desiredNumber; ++i){
      var newGhost = ghostFactory.createObject(root)
      newGhost.anchors.verticalCenter = root.verticalCenter
      ghosts.push(newGhost)
    }
  }

  Component{
      id: ghostFactory
      Ghost{}
  }

  property var dragTarget: null

}
