/*
 * BigBlueButton - http://www.bigbluebutton.org
 * 
 * Copyright (c) 2008-2009 by respective authors (see below). All rights reserved.
 * 
 * BigBlueButton is free software; you can redistribute it and/or modify it under the 
 * terms of the GNU Lesser General Public License as published by the Free Software 
 * Foundation; either version 3 of the License, or (at your option) any later 
 * version. 
 * 
 * BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY 
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A 
 * PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License along 
 * with BigBlueButton; if not, If not, see <http://www.gnu.org/licenses/>.
 *
 * $Id: $
 */
package org.bigbluebutton.modules.viewers.business
{
	import com.asfusion.mate.events.Dispatcher;
	
	import flash.events.AsyncErrorEvent;
	import flash.events.NetStatusEvent;
	import flash.net.NetConnection;
	import flash.net.Responder;
	import flash.net.SharedObject;
	
	import mx.controls.Alert;
	
	import org.bigbluebutton.common.LogUtil;
	import org.bigbluebutton.main.events.BBBEvent;
	import org.bigbluebutton.main.events.ParticipantJoinEvent;
	import org.bigbluebutton.main.events.PresenterStatusEvent;
	import org.bigbluebutton.main.model.User;
	import org.bigbluebutton.modules.viewers.events.ConnectionFailedEvent;
	import org.bigbluebutton.modules.viewers.events.RoleChangeEvent;

	public class ViewersSOService
	{
		public static const NAME:String = "ViewersSOService";
		public static const LOGNAME:String = "[ViewersSOService]";
		
		private var _participantsSO : SharedObject;
		private static const SO_NAME : String = "participantsSO";
		private static const STATUS:String = "_STATUS";
		
		private var netConnectionDelegate: NetConnectionDelegate;
		
		private var _participants:Conference;
		private var _mode:String;
		private var _room:String;
		
		private var _module:ViewersModule;
		
		private var dispatcher:Dispatcher;
				
		public function ViewersSOService(m:ViewersModule, participants:Conference)
		{			
			_module = m;
			_participants = participants;
			netConnectionDelegate = new NetConnectionDelegate(_module);
			dispatcher = new Dispatcher();
		}
		
		public function connect(username:String, role:String, conference:String, mode:String, room:String, externUserID:String):void {
			_mode = mode;
			_room = room;
			netConnectionDelegate.connect(username, role, conference, mode, room, externUserID);
		}
			
		public function disconnect():void {
			leave();
			netConnectionDelegate.disconnect();
		}
		
	    public function join(userid:Number) : void
		{
			_participantsSO = SharedObject.getRemote(SO_NAME, _module.uri, false);
			_participantsSO.addEventListener(NetStatusEvent.NET_STATUS, netStatusHandler);
			_participantsSO.addEventListener(AsyncErrorEvent.ASYNC_ERROR, asyncErrorHandler);
			_participantsSO.client = this;
			_participantsSO.connect(netConnectionDelegate.connection);
			LogUtil.debug(LOGNAME + ":ViewersModules is connected to Shared object");
			if (_mode == 'PLAYBACK') {
				startPlayback()
			} else {
				queryForParticipants();
			}			
			
			_participants.me.userid = userid;
		}
		
		private function startPlayback():void {
			var nc:NetConnection = netConnectionDelegate.connection;
			nc.call(
				"archive.startPlayback",// Remote function name
				new Responder(
	        		// participants - On successful result
					function(result:Object):void { 
						LogUtil.debug("Successfully started playback: "); 
						//notifyConnectionStatusListener(true, ViewersModuleConstants.PLAYBACK_STARTED);
					},	
					// status - On error occurred
					function(status:Object):void { 
						LogUtil.error("Error occurred:"); 
						for (var x:Object in status) { 
							LogUtil.error(x + " : " + status[x]); 
							} 
						//notifyConnectionStatusListener(false, "Failed to join the conference.");
					}
				),//new Responder
				_module.playbackRoom
			); //_netConnection.call
		}
		
		private function queryForParticipants():void {
			var nc:NetConnection = netConnectionDelegate.connection;
			nc.call(
				"participants.getParticipants",// Remote function name
				new Responder(
	        		// participants - On successful result
					function(result:Object):void { 
						LogUtil.debug("Successfully queried participants: " + result.count); 
						if (result.count > 0) {
							for(var p:Object in result.participants) 
							{
								participantJoined(result.participants[p]);
							}		
							//notifyConnectionStatusListener(true, ViewersModuleConstants.QUERY_PARTICIPANTS_REPLY);
							trace("Am I the only moderator?");
							LogUtil.debug("Am I the only moderator?");
							becomePresenterIfLoneModerator();				
						}	
						
					},	
					// status - On error occurred
					function(status:Object):void { 
						LogUtil.error("Error occurred:"); 
						for (var x:Object in status) { 
							LogUtil.error(x + " : " + status[x]); 
							} 
						sendConnectionFailedEvent(ConnectionFailedEvent.UNKNOWN_REASON);
					}
				)//new Responder
			); //_netConnection.call
		}
		
		private function becomePresenterIfLoneModerator():void {
			if (_participants.hasOnlyOneModerator()) {
				trace("There is only one moderator");
				var user:BBBUser = _participants.getTheOnlyModerator();
				if (user.me) {
					trace("I am the only moderator");
					var presenterEvent:RoleChangeEvent = new RoleChangeEvent(RoleChangeEvent.ASSIGN_PRESENTER);
					presenterEvent.userid = user.userid;
					presenterEvent.username = user.name;
					dispatcher.dispatchEvent(presenterEvent);
				} else {
					trace("The moderator is not me");
				}
			} else {
				trace("I am not the only moderator");
			}
			
		}
		
	    private function leave():void
	    {
	    	if (_participantsSO != null) _participantsSO.close();
	    }
		
		public function participantLeft(user:Object):void { 			
			var participant:BBBUser = _participants.getParticipant(Number(user));
			
			var p:User = new User();
			p.userid = String(participant.userid);
			p.name = participant.name;
			
			var dispatcher:Dispatcher = new Dispatcher();
			var joinEvent:ParticipantJoinEvent = new ParticipantJoinEvent(ParticipantJoinEvent.PARTICIPANT_JOINED_EVENT);
			joinEvent.participant = p;
			joinEvent.join = false;
			dispatcher.dispatchEvent(joinEvent);	
			
			_participants.removeParticipant(Number(user));	
		}
		
		public function participantJoined(joinedUser:Object):void { 
			var user:BBBUser = new BBBUser();
			user.userid = Number(joinedUser.userid);
			user.name = joinedUser.name;
			user.role = joinedUser.role;

			LogUtil.debug("User status: " + joinedUser.status.hasStream);

			LogUtil.info("Joined as [" + user.userid + "," + user.name + "," + user.role + "]");
			_participants.addUser(user);

			participantStatusChange(user.userid, "hasStream", joinedUser.status.hasStream);
			participantStatusChange(user.userid, "streamName", joinedUser.status.streamName);
			participantStatusChange(user.userid, "presenter", joinedUser.status.presenter);
			participantStatusChange(user.userid, "raiseHand", joinedUser.status.raiseHand);

			var participant:User = new User();
			participant.userid = String(user.userid);
			participant.name = user.name;
			participant.isPresenter = joinedUser.status.presenter;
			participant.role = user.role;
			
			var dispatcher:Dispatcher = new Dispatcher();
			var joinEvent:ParticipantJoinEvent = new ParticipantJoinEvent(ParticipantJoinEvent.PARTICIPANT_JOINED_EVENT);
			joinEvent.participant = participant;
			joinEvent.join = true;
			dispatcher.dispatchEvent(joinEvent);				
		}
		
		public function logout():void {
			var dispatcher:Dispatcher = new Dispatcher();
			var endMeetingEvent:BBBEvent = new BBBEvent("EndMeetingKickAllEvent");
			dispatcher.dispatchEvent(endMeetingEvent);
		}
		
		public function participantStatusChange(userid:Number, status:String, value:Object):void {
			LogUtil.debug("Received status change [" + userid + "," + status + "," + value + "]")
			
			_participants.newUserStatus(userid, status, value);
			
			if (status == "presenter"){
				var e:PresenterStatusEvent = new PresenterStatusEvent(PresenterStatusEvent.PRESENTER_NAME_CHANGE);
				e.userid = userid;
				var dispatcher:Dispatcher = new Dispatcher();
				dispatcher.dispatchEvent(e);
			}
			
		}
					
		public function assignPresenter(userid:Number, assignedBy:Number):void {
	
			var nc:NetConnection = netConnectionDelegate.connection;
			nc.call(
				"participants.assignPresenter",// Remote function name
				new Responder(
	        		// participants - On successful result
					function(result:Boolean):void { 						 
						if (result) {
							LogUtil.debug("Successfully assigned presenter to: " + userid);							
						}	
					},	
					// status - On error occurred
					function(status:Object):void { 
						LogUtil.error("Error occurred:"); 
						for (var x:Object in status) { 
							LogUtil.error(x + " : " + status[x]); 
							} 
					}
				), //new Responder
				userid,
				assignedBy
			); //_netConnection.call
		}
/*		
		public function assignPresenterCallback(userid:Number, assignedBy:Number):void {
			sendMessage(ViewersModuleConstants.ASSIGN_PRESENTER, {assignedTo:userid, assignedBy:assignedBy});
		}
		
		public function queryPresenter():void {
		
		}
*/

		public function raiseHand(userid:Number, raise:Boolean):void {
			var nc:NetConnection = netConnectionDelegate.connection;			
			nc.call(
				"participants.setParticipantStatus",// Remote function name
				new Responder(
	        		// participants - On successful result
					function(result:Boolean):void { 
						 
						if (result) {
							LogUtil.debug("Successfully assigned raise hand to: " + userid);							
						}	
					},	
					// status - On error occurred
					function(status:Object):void { 
						LogUtil.error("Error occurred:"); 
						for (var x:Object in status) { 
							LogUtil.error(x + " : " + status[x]); 
							} 
					}
				), //new Responder
				userid,
				"raiseHand",
				raise
			); //_netConnection.call
		}
		
		public function addStream(userid:Number, streamName:String):void {
			var nc:NetConnection = netConnectionDelegate.connection;
			nc.call(
				"participants.setParticipantStatus",// Remote function name
				new Responder(
	        		// participants - On successful result
					function(result:Boolean):void { 
						 
						if (result) {
							LogUtil.debug("Successfully assigned stream to: " + userid);							
						}	
					},	
					// status - On error occurred
					function(status:Object):void { 
						LogUtil.error("Error occurred:"); 
						for (var x:Object in status) {
							LogUtil.error(x + " : " + status[x]);
							}
					}
				), //new Responder
				userid,
				"streamName",
				streamName
			); //_netConnection.call
			
			nc.call(
				"participants.setParticipantStatus",// Remote function name
				new Responder(
	        		// participants - On successful result
					function(result:Boolean):void { 
						 
						if (result) {
							LogUtil.debug("Successfully assigned stream to: " + userid);							
						}	
					},	
					// status - On error occurred
					function(status:Object):void { 
						LogUtil.error("Error occurred:"); 
						for (var x:Object in status) { 
							LogUtil.error(x + " : " + status[x]); 
							} 
					}
				), //new Responder
				userid,
				"hasStream",
				true
			); //_netConnection.call
		}
		
		public function removeStream(userid:Number, streamName:String):void {
			var nc:NetConnection = netConnectionDelegate.connection;
			nc.call(
				"participants.setParticipantStatus",// Remote function name
				new Responder(
	        		// participants - On successful result
					function(result:Boolean):void { 
						 
						if (result) {
							LogUtil.debug("Successfully assigned stream to: " + userid);							
						}	
					},	
					// status - On error occurred
					function(status:Object):void { 
						LogUtil.error("Error occurred:"); 
						for (var x:Object in status) { 
							LogUtil.error(x + " : " + status[x]); 
							} 
					}
				), //new Responder
				userid,
				"streamName",
				""
			); //_netConnection.call
			
			nc.call(
				"participants.setParticipantStatus",// Remote function name
				new Responder(
	        		// participants - On successful result
					function(result:Boolean):void { 
						 
						if (result) {
							LogUtil.debug("Successfully removed stream to: " + userid);							
						}	
					},	
					// status - On error occurred
					function(status:Object):void { 
						LogUtil.error("Error occurred:"); 
						for (var x:Object in status) { 
							LogUtil.error(x + " : " + status[x]); 
							} 
					}
				), //new Responder
				userid,
				"hasStream",
				false
			); //_netConnection.call
		}

		private function netStatusHandler ( event : NetStatusEvent ) : void
		{
			var statusCode : String = event.info.code;
			
			switch ( statusCode ) 
			{
				case "NetConnection.Connect.Success" :
					LogUtil.debug(LOGNAME + ":Connection Success");		
					sendConnectionSuccessEvent();			
					break;
			
				case "NetConnection.Connect.Failed" :			
					LogUtil.debug(LOGNAME + ":Connection to viewers application failed");
					sendConnectionFailedEvent(ConnectionFailedEvent.CONNECTION_FAILED);
					break;
					
				case "NetConnection.Connect.Closed" :									
					LogUtil.debug(LOGNAME + ":Connection to viewers application closed");
					sendConnectionFailedEvent(ConnectionFailedEvent.CONNECTION_CLOSED);
					break;
					
				case "NetConnection.Connect.InvalidApp" :				
					LogUtil.debug(LOGNAME + ":Viewers application not found on server");
					sendConnectionFailedEvent(ConnectionFailedEvent.INVALID_APP);
					break;
					
				case "NetConnection.Connect.AppShutDown" :
					LogUtil.debug(LOGNAME + ":Viewers application has been shutdown");
					sendConnectionFailedEvent(ConnectionFailedEvent.APP_SHUTDOWN);
					break;
					
				case "NetConnection.Connect.Rejected" :
					LogUtil.debug(LOGNAME + ":No permissions to connect to the viewers application" );
					sendConnectionFailedEvent(ConnectionFailedEvent.CONNECTION_REJECTED);
					break;
					
				default :
				   LogUtil.debug(LOGNAME + ":default - " + event.info.code );
				   sendConnectionFailedEvent(ConnectionFailedEvent.UNKNOWN_REASON);
				   break;
			}
		}
			
		private function asyncErrorHandler ( event : AsyncErrorEvent ) : void
		{
			LogUtil.debug(LOGNAME + "participantsSO asyncErrorHandler " + event.error);
			sendConnectionFailedEvent(ConnectionFailedEvent.ASYNC_ERROR);
		}
		
		public function get connection():NetConnection
		{
			return netConnectionDelegate.connection;
		}
		
		private function sendConnectionFailedEvent(reason:String):void{
			var e:ConnectionFailedEvent = new ConnectionFailedEvent();
			e.reason = reason;
			dispatcher.dispatchEvent(e);
		}
		
		private function sendConnectionSuccessEvent():void{
			//TODO
		}
	}
}