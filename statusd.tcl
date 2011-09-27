namespace eval statusd {
########################################################################
# Copyright ©2011 lee8oi@gmail.com
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
# http://www.gnu.org/licenses/
#
# Statusd v0.2.3beta (9.27.11)
# by: <lee8oiAtgmail><lee8oiOnfreenode>
# github link: https://github.com/lee8oi/statusd/blob/master/statusd.tcl
#
# Status oriented rebuild of Seend v1.8.3
#
# -------------------------------------------------------------------
#
# Statusd is a re-imagining of Seend script that was designed to track users
# latest status in any channels with the correct channel flag set. Users can
# check the status of a nick in a specific channel or check for most recent
# activity regardless of channel. If nick specified is not found the script
# will search for the pattern in existing names. Status checks can be done in 
# channel or query/msg. Script also includes automatic backup system that saves 
# on .die, restart, timed intervals, and by backup trigger in msg/query. 
#
# *When no channel argument is provided statusd can default to using the current 
# channel or to use the channel with most recent activity. Applies only to
# status checks done in channel. See configuration section below.
#
# Status's tracked: Joined, Parted, Kicked, Quit, Nick Change, Spoke, and Action.
#
# Initial channel setup:
# (starts logging and enables public status command. Run in partyline.)
# .chanset #channel +statusd
#
# Public command syntax:
# !status <nick> ?channel?
#
# Example Usage:
# (public)
# <lee8oi> !status lee8oi
# <dukelovett>  lee8oi spoke in #dukelovett 4 minutes 21 seconds ago. Message:
# I thought it was a great idea so I got started.
# <lee8oi> !status lee8oi #dukelovett2
# <dukelovett> lee8oi joined #dukelovett2 5 minutes 59 seconds ago.
#
# Thanks: drsprite. This script was concieved from your suggestions & comments.
#
# Updates:
# v0.2
#  1. Fixed channel arg to be case insensitive.
#  2. Added new feature. If nick specified is not found script will search for 
#  names which include the pattern. If channel arg is provided search will
#  only look for matches in that channel.
#  3.In the process of adding userhost related features.
# 
# -------------------------------------------------------------------
# Configuration:
#
#  *Set command trigger
#                     +-------+
variable trigger       !status
#                     +-------+
#
#  *Set backup command trigger
#     can be used in msg/query by bot owners to trigger an immediate backup.
#                       +-------+
variable backup_trigger  !backup
#                       +-------+
#
#  *Set backupfile location/name
#                     +--------------------------+
variable backupfile    "scripts/statusdData.tcl"
#                     +--------------------------+
#
#  *Set backup interval time (in mins)
#                     +---+
variable interval       5
#                     +---+
#
#  *Log backup messages
#     1 = on, 0 = off
#                     +---+
variable logbackups     0
#                     +---+
#
#  *Use current channel if no channel specified(channel only)
#     -Off defaults to using the channel with most recent activity.
#     1 = on, 0 = off
#                         +---+
variable use_current_chan   1
#                         +---+
#
########################################################################
variable timeseen
variable lastmsg
variable status
variable statustime
variable statustext
variable lastchan
variable nickcase
variable nickhost
variable ver "0.2.3beta"
setudef flag statusd
}
bind msg n [set ::statusd::backup_trigger] ::statusd::backup_data
bind msg - [set ::statusd::trigger] ::statusd::msg_show_status
bind pub - [set ::statusd::trigger] ::statusd::show_status
bind pubm - * ::statusd::status_logger_pubm
bind sign - * ::statusd::status_logger_sign
bind part - * ::statusd::status_logger_part
bind join - * ::statusd::status_logger_join
bind kick - * ::statusd::status_logger_kick
bind nick - * ::statusd::status_logger_nick
bind evnt - prerestart ::statusd::prerestart
bind evnt - loaded ::statusd::loaded
bind ctcp - "ACTION" ::statusd::status_logger_action
if {![info exists ::statusd_dietrace]} {
   # .die trigger. do backup
   trace add execution *dcc:die enter ::statusd::backup_data
   trace add execution *msg:die enter ::statusd::backup_data
}
if {![info exists statusd_timer_running]} {
   # no existing timer. start new one.
   timer [set ::statusd::interval] ::statusd::timer_proc
   set statusd_timer_running 1
}
namespace eval statusd {
   proc restore {args} {
      # restore from file
      if {[file exist [set ::statusd::backupfile]]} {
         source [set ::statusd::backupfile]
      }
   }
   proc prerestart {type} {
      # prerestart trigger. do backup.
      ::statusd::backup_data
      putlog "Status Data Saved."
   }
   proc loaded {type} {
      # bot loaded trigger do restore.
      ::statusd::restore
   }
   proc timer_proc {args} {
      # call self at timed intervals. do backup
      ::statusd::backup_data
      timer [set ::statusd::interval] ::statusd::timer_proc
      return 1
   }
   proc backup_data {args} {
      # backup to file: Write lines to file so it can
      # be sourced as a script during restore.
      variable ::statusd::status
      variable ::statusd::nickcase
      variable ::statusd::lastchan
      variable ::statusd::statustime
      variable ::statusd::statustext
      set fs [open [set ::statusd::backupfile] w+]
      # write variable lines for loading namespace vars.
      puts $fs "variable ::statusd::status"
      puts $fs "variable ::statusd::nickcase"
      puts $fs "variable ::statusd::lastchan"
      puts $fs "variable ::statusd::statustime"
      puts $fs "variable ::statusd::statustext"
      # create 'array set' lines using array data.
      foreach arr {status nickcase lastchan statustime statustext} {
         puts $fs "array set $arr [list [array get $arr]]"
      }
      close $fs;
      if {[set ::statusd::logbackups]} {
         # logging is enabled.
         putlog "Status backup performed."
      }
   }
   proc search_names {searchterm channel} {
      variable ::statusd::nickcase
      variable ::statusd::status
      set channel [string tolower $channel]
      set lterm [string tolower $searchterm]
      set namelist [array names nickcase "\*${lterm}\*"]
      if { $namelist != "" } {
         # names matching pattern exist.
         set newlist ""
         if {[regexp {^\#} $channel]} {
            foreach elem $namelist {
               if {[info exists status($elem,$channel)]} {
                  append newlist " " $nickcase($elem)
               }
            }
            if {$newlist != ""} {
               set result "'${searchterm}' matches from $channel: $newlist"
            } else {
               set result "'${searchterm}' not found."
            }
         } elseif {$channel == ""} {
            foreach elem $namelist {
               if {[info exists nickcase($elem)]} {
                  append newlist " " $nickcase($elem)
               }
            }
            if {$newlist != ""} {
               set result "'${searchterm}' matches: $newlist"
            } else {
               set result "'${searchterm}' not found."
            }
         }
         
      } else {
         set result "'${searchterm}' not found."
      }
      return $result
   }
   proc search_hosts {searchterm} {
   variable ::statusd::nickhost
   set hostlist [array names nickhost "${searchterm}"]
   if { $hostlist != "" } {      
      set result "'${searchterm}' host matches the following nicks: $hostlist"      
   } else {
      set result "'${searchterm}' not found."
   }
   return $result
   }
   proc set_status {nick userhost channel status text} {
      set lnick [string tolower $nick]
      set lchan [string tolower $channel]
      set ::statusd::status($lnick,$lchan) $status
      set ::statusd::statustext($lnick,$lchan) $text
      set ::statusd::statustime($lnick,$lchan) [clock seconds]
      set ::statusd::nickcase($lnick) $nick
      set ::statusd::nickhost($lnick) $userhost
      set ::statusd::lastchan($lnick) $lchan
   }
   proc get_status {nick channel} {
      set lnick [string tolower $nick]
      set lchan [string tolower $channel]
      set lstatus [set ::statusd::status($lnick,$lchan)]
      set ltext [set ::statusd::statustext($lnick,$lchan)]
      set ltime [set ::statusd::statustime($lnick,$lchan)]
      set ncase [set ::statusd::nickcase($lnick)]
      set durat [duration [expr {[clock seconds] - $ltime}]]
      if {$lstatus == "Quit"} {
         set result "$ncase was last seen quitting $durat ago. $ltext"
      } elseif {$lstatus == "Parted"} {
         set result "$ncase was last seen Parting from $channel $durat ago."
      } elseif {$lstatus == "Joined"} {
         set result "$ncase joined $channel $durat ago."
      } elseif {$lstatus == "Kicked"} {
         set result "$ncase was kicked from $channel $durat ago. Reason: $ltext"
      } elseif {$lstatus == "Nick Change"} {
         set result "$ncase was last seen changing name $ltext $durat ago."
      } elseif {$lstatus == "Spoke"} {
         set result "$ncase spoke in $channel $durat ago. Message: $ltext"
      } elseif {$lstatus == "Action"} {
         set result "$ncase was seen acting in $channel $durat ago: * $ncase $ltext"
      } else {
         set result "Status error. Unknown status type."
      }
      return $result
   }
   proc msg_show_status {nick userhost handle text} {
      #Status check via msg/query
      set arg1 [lindex [split $text] 0]
      set arg2 [lindex [split $text] 1]
      set larg1 [string tolower $arg1]
      variable ::statusd::status
      variable ::statusd::lastchan
      if {$arg2 != "" && [regexp {^\#} $arg2]} {
         #2nd arg is channel
         if {[info exists status($larg1,$arg2)]} {
            #status available.
            set vstatus [::statusd::get_status $arg1 $arg2]
         } else {
            set vstatus [::statusd::search_names $arg1 $arg2]
         }
         putserv "PRIVMSG $nick :$vstatus"
      } elseif {$arg2 == "" && $arg1 != ""} {
         #no channel specified. nick only.
         if {[info exists lastchan($larg1)]} {
            set lastch [set lastchan($larg1)]
         } else {
            set lastch "#NOCHAN"
         }
         if {[info exists status($larg1,$lastch)]} {
            #status available
            set vstatus [::statusd::get_status $arg1 $lastch]
         } else {
            set vstatus [::statusd::search_names $arg1 ""]
         }
         putserv "PRIVMSG $nick :$vstatus"
      } else {
         #no args provided.
         variable ::statusd::ver
         set pubcom [set ::statusd::trigger]
         putserv "PRIVMSG $nick :Usage: $pubcom <nick> ?channel?"
      }
   }
   proc show_status {nick userhost handle channel text} {
      #status check via channel
      if {[channel get $channel statusd]} {
         set arg1 [lindex [split $text] 0]
         set arg2 [lindex [split $text] 1]
         set larg1 [string tolower $arg1]
         variable ::statusd::status
         if {$arg2 != "" && [regexp {^\#} $arg2]} {
            #2nd arg is channel
            if {[info exists status($larg1,$arg2)]} {
               #status available.
               set vstatus [::statusd::get_status $arg1 $arg2]
            } else {
               #fall back to pattern search.
               set vstatus [::statusd::search_names $arg1 $arg2]
            }
            putserv "PRIVMSG $channel :$vstatus"
         } elseif {$larg1 == 'host' && $arg2 != ""} {
            set vstatus [::statusd::search_hosts $arg2]
            putserv "PRIVMSG $channel :$vstatus"
         } elseif {$arg2 == "" && $arg1 != ""} {
            #no channel specified. nick only.
            if {[set ::statusd::use_current_chan]} {
               #use current chan
               set chanvar $channel
            } else {
               #use most recent channel
               if {[info exists ::statusd::lastchan($larg1)]} {
                  #Use recorded last channel.
                  set chanvar [set ::statusd::lastchan($larg1)]
               } else {
                  #fall back to current channel.
                  set chanvar $channel
               }
            }
            if {[info exists status($larg1,$chanvar)]} {
               #status available
               set vstatus [::statusd::get_status $arg1 $chanvar]
            } else {
               #no status available. Do pattern search
               set vstatus [::statusd::search_names $arg1 $chanvar]
            }
            putserv "PRIVMSG $channel :$vstatus"
         } else {
            #no args provided.
            variable ::statusd::ver
            set pubcom [set ::statusd::trigger]
            putserv "PRIVMSG $channel :Usage: $pubcom <nick> ?channel?"
         }
      }
   }
   proc status_logger_pubm {nick userhost handle channel text} {
      #public channel message logger.
      if {[channel get $channel statusd]} {
         set arg1 [lindex [split $text] 0]
         if {$arg1 != [set ::statusd::trigger]} {
             # not a status request. Ok to save.
             ::statusd::set_status $nick $userhost $channel "Spoke" $text
         }
      }
   }
   proc status_logger_sign {nick userhost handle channel text} {
      if {[channel get $channel statusd]} {
         ::statusd::set_status $nick $userhost $channel "Quit" $text
      }
   }
   proc status_logger_part {nick userhost handle channel text} {
      if {[channel get $channel statusd]} {
         ::statusd::set_status $nick $userhost $channel "Parted" ""
      }
   }
   proc status_logger_join {nick userhost handle channel} {
      if {[channel get $channel statusd]} {
         ::statusd::set_status $nick $userhost $channel "Joined" ""
      }
   }
   proc status_logger_kick {nick userhost handle channel target reason} {
      if {[channel get $channel statusd]} {
         ::statusd::set_status $target "none@none" $channel "Kicked" $reason
      }
   }
   proc status_logger_nick {nick userhost handle channel newnick} {
      if {[channel get $channel statusd]} {
         ::statusd::set_status $nick $userhost $channel "Nick Change" "to $newnick"
         ::statusd::set_status $newnick $userhost $channel "Nick Change" "from $nick"
      }
   }
   proc status_logger_action { nick userhost hand dest keyword text } {  
     if {[string index $dest 0] != "#"} { return 0 }        
     if {[channel get $dest statusd]} {
         ::statusd::set_status $nick $userhost $dest "Action" $text
      }
  }
}
putlog "Statusd [set ::statusd::ver] loaded."