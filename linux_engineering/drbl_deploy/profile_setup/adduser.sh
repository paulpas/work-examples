#!/bin/bash
# Add user and email config and Noble softphone config based on formatted user list or manual entry:
#
#### FORMAT ####
# First Last:fields:here:reserved:for:future:use
# First Last:
# First Last
################
#
script=`basename $0`
arg1=$1
arg2=$2

function main {
	case $arg1 in
	-b|--batch) batch_main ;; # batch user implement ## done verifying functionality, success!
	-a|--add) menu_main ;; # menu driven manual entry
	-d|--delete) delete_main ;; # menu driven delete user menu
	*) usage ;;
	esac
}

function usage {
	echo
	echo
	echo "Usage:"
	echo "$script -b /path/to/users/file"
	echo "$script -a \"John Smith\""
	echo "$script -d \"John Smith\""
	echo
	echo
	exit 1
}
	
function change_ownership {
	chown -R $uname.$uname /home/$uname
}

function delete_user {
	(deluser $uname && rm -rf /home/$uname) || echo "Username $uname not found in /etc/passwd!  Delete $USERHOME manually on CLI." # if $HOME exists, then verify username exits
}

function user_exists {
	grep "^$uname:" /etc/passwd &>/dev/null || unameexists=$?
     	echo $unameexists
}

function check_user_exists_and_delete {
	user_exists
	USERHOME=/home/$uname
	if [[ $unameexists != 1 ]] # if user exists, then we can delete
	then
		delete_user || echo "User $uname directory $USERHOME does not exist.  Manually delete user on CLI!"
		if [ -d $USERHOME ] # check for user directory
			then
				delete_user
		fi
	fi
}

function delete_main {
	if [[ -z $arg2 ]]
	then
		usage
	else
		name="$arg2"
		uname=`echo $name | sed 's/\./\ /1;s/\(\<.\).*\ /\1/' | tr [:upper:] [:lower:]`
		check_user_exists_and_delete
	fi
}	

function menu_main {
	if [[ -z $arg2 ]]
	then
		usage
	else
		name="$arg2"
		uname=`echo $name | sed 's/\./\ /1;s/\(\<.\).*\ /\1/' | tr [:upper:] [:lower:]`
		main_add_user
		siphone_profile_generate
		icedove_profile_generate
		change_ownership
	fi
}

function batch_main {
	if [[ ! -f $arg2 ]]
	then
		usage
	else
		exec 3<$arg2
		IFS=$'\n'
		for i in `cat $arg2`
		do
			name=`echo $i | awk -F: '{print $1}'`
			uname=`echo $name | sed 's/\./\ /1;s/\(\<.\).*\ /\1/' | tr [:upper:] [:lower:]`
			batch_add_user
			siphone_profile_generate
			icedove_profile_generate
			change_ownership
		done <&3
	fi
}

function nis_passwd {
	make -C /var/yp # Apply to NIS
}


function main_passwd {
	echo $uname:$pass | chpasswd
	nis_passwd
}

function batch_passwd {
	pass="p@ssw0rd" # default password
	echo $uname:$pass | chpasswd
	nis_passwd
}

function add_user_passwd_method {
		echo "Username $uname is unique, proceeding to add the user."	
		read -s -p "Enter password for user $uname: " pass
		echo
		read -s -p "Enter again: " pass1
		if [[ $pass == $pass1 ]]
		then
			adduser --disabled-login --gecos "$name" $uname # || echo "Error on user generation.  Exiting." && exit 1
			main_passwd
		else
			echo "Passwords to not match, try again:"
			main_add_user
		fi

}
function main_add_user { # this does not work yet, do not add user Paul - 04/19/2013
	user_exists
	if [[ $unameexists != 1 ]] # if user exists
	then
		echo  "Username $uname already exists, please choose custom username:"
		read uname
		user_exists
		if [[ $unameexists != 1 ]] # if user exists
		then
			add_user_passwd_method
		else
			main_add_user
		fi
	else
		add_user_passwd_method
	fi
}
function batch_add_user {
	adduser --disabled-login --gecos "$name" $uname # >/dev/null || echo "Error on user generation.  Exiting." && exit 1
	batch_passwd
}

function get_extension { # Find highest extension in use and add 1 to it
	high_used_extension=`find /home -name siphone.conf | xargs grep 30.. | grep username | awk -F\> '{print $2}' | awk -F\< '{print $1}' | sort -n | tail -1`
	ext=`echo $((high_used_extension+1))`
}

function siphone_profile_generate {

get_extension

cat << EOF > /tmp/siphone.conf
<?xml version="1.0" encoding="UTF-8"?>
<options>
  <general>
    <record_calls>0</record_calls>
    <record_path></record_path>
    <always_on_top>0</always_on_top>
    <automatic_popup_on_incoming_call>1</automatic_popup_on_incoming_call>
    <default_account>$ext</default_account>
    <popup_menu_on_incoming_call>1</popup_menu_on_incoming_call>
    <start_with_os>0</start_with_os>
    <start_minimized>0</start_minimized>
    <automatic_url_open>0</automatic_url_open>
    <use_custom_browser>0</use_custom_browser>
    <custom_browser></custom_browser>
    <open_url_on_style>0</open_url_on_style>
    <open_url/>
    <language>English</language>
    <strip_dial_chars>+-()[]{}</strip_dial_chars>
    <on_transfer_request_style>2</on_transfer_request_style>
    <forward_type>0</forward_type>
    <forward_seconds>30</forward_seconds>
    <forward_extension></forward_extension>
    <autoanswer_seconds>30</autoanswer_seconds>
    <play_sound_on_auto_answer>1</play_sound_on_auto_answer>
    <keep_settings_after_restart>0</keep_settings_after_restart>
    <auto_answer>0</auto_answer>
    <call_forwarding>0</call_forwarding>
    <number_of_lines>6</number_of_lines>
  </general>
  <sip_options>
    <port>5060</port>
    <tls_certificate_file></tls_certificate_file>
  </sip_options>
  <iax_options>
    <port>4569</port>
  </iax_options>
  <rtp_options>
    <port>8000</port>
    <session_name>SIPhone_session</session_name>
    <user_name>SIPhone_user</user_name>
    <url>www.noblesys.com</url>
    <email>support@noblesys.com</email>
  </rtp_options>
  <stun_options>
    <use_stun>0</use_stun>
    <host>stun.zoiper.com</host>
    <port>3478</port>
    <stun_refresh_period>30</stun_refresh_period>
  </stun_options>
  <accounts>
    <account>
      <tech>0</tech>
      <name>$ext</name>
      <host></host>
      <username>$ext</username>
      <password>c2EYn3sDdraulmgU+OBy6Q==
</password>
      <context>172.18.10.99</context>
      <callerid></callerid>
      <number></number>
      <authentication_username></authentication_username>
      <use_outbound_proxy>0</use_outbound_proxy>
      <transport_type>0</transport_type>
      <use_rport>0</use_rport>
      <use_rport_media>0</use_rport_media>
      <force_rfc3264>0</force_rfc3264>
      <mwi_subscribe_usage>3</mwi_subscribe_usage>
      <dtmf_style>1</dtmf_style>
      <register_on_startup>1</register_on_startup>
      <reregistration_time>3600</reregistration_time>
      <subscribe_time>3600</subscribe_time>
      <do_not_play_ringback_tones>0</do_not_play_ringback_tones>
      <voicemail_check_extension></voicemail_check_extension>
      <use_stun>0</use_stun>
      <stun_host></stun_host>
      <stun_port>0</stun_port>
      <stun_refresh_period>0</stun_refresh_period>
      <custom_codecs>0</custom_codecs>
    </account>
  </accounts>
  <audio>
    <input_device>Andrea PureAudio USB-SA Headset: USB Audio (hw:1,0)</input_device>
    <output_device>Andrea PureAudio USB-SA Headset: USB Audio (hw:1,0)</output_device>
    <ringing_device>Andrea PureAudio USB-SA Headset: USB Audio (hw:1,0)</ringing_device>
    <use_echo_cancellation>1</use_echo_cancellation>
    <use_audio_enhancement>0</use_audio_enhancement>
    <ring_tone_file></ring_tone_file>
    <mute_on_ringing>0</mute_on_ringing>
    <ring_when_talking>1</ring_when_talking>
    <pc_speaker_ring>0</pc_speaker_ring>
    <disable_dtmf_sounds>0</disable_dtmf_sounds>
    <input_volume>1.0</input_volume>
    <output_volume>1.0</output_volume>
  </audio>
  <codecs>
    <codec>
      <name>G729</name>
      <codec_id>16</codec_id>
      <priority>1</priority>
      <selected>1</selected>
    </codec>
    <codec>
      <name>iLBC 30</name>
      <codec_id>27</codec_id>
      <priority>65535</priority>
      <selected>0</selected>
    </codec>
    <codec>
      <name>GSM</name>
      <codec_id>1</codec_id>
      <priority>65535</priority>
      <selected>0</selected>
    </codec>
    <codec>
      <name>Speex</name>
      <codec_id>24</codec_id>
      <priority>65535</priority>
      <selected>0</selected>
    </codec>
    <codec>
      <name>a-law</name>
      <codec_id>6</codec_id>
      <priority>65535</priority>
      <selected>0</selected>
    </codec>
    <codec>
      <name>u-law</name>
      <codec_id>0</codec_id>
      <priority>65535</priority>
      <selected>0</selected>
    </codec>
    <use_default_speex_settings>1</use_default_speex_settings>
    <enhance_decoding>0</enhance_decoding>
    <quality>4.0</quality>
    <bitrate>9</bitrate>
    <variable_bit_rate>0</variable_bit_rate>
    <average_bit_rate>9</average_bit_rate>
    <complexity>3</complexity>
  </codecs>
  <transfer>
    <park_extension></park_extension>
    <voicemail_prefix></voicemail_prefix>
  </transfer>
  <provision>
    <remember_username_password>0</remember_username_password>
    <login_automatically>0</login_automatically>
    <username></username>
    <password></password>
  </provision>
  <diagnostics>
    <enable_debug_log>1</enable_debug_log>
  </diagnostics>
  <fax>
    <fax_enabled>1</fax_enabled>
    <automatic_display>1</automatic_display>
    <automatic_print>1</automatic_print>
    <destination_folder></destination_folder>
    <custom_command></custom_command>
  </fax>
  <network>
    <signal_dscp>-1</signal_dscp>
    <media_dscp>-1</media_dscp>
  </network>
</options>
EOF

	mkdir -p /home/$uname/.siphone/
        cp -pr /tmp/siphone.conf /home/$uname/.siphone/
}

function icedove_profile_generate {

	fullname="$name"
	username="$uname"
	# Do not edit below unless you're the sysadmin
	domain=mail.titleloanplace.com
	imap=mail.tmxcredit.net
	imapport=993
	smtp=mail.tmxcredit.net
	smtpport=465
	emailaddress=$username@$domain


	# Generating an 8-character "random" string.

	if [ -n "$1" ]  #  If command-line argument present,
	then            #+ then set start-string to it.
	  str0="$1"
	else            #  Else use PID of script as start-string.
	  str0="$$"
	fi

	POS=2  # Starting from position 2 in the string.
	LEN=8  # Extract eight characters.

	str1=$( echo "$str0" | md5sum | md5sum )
	# Doubly scramble:     ^^^^^^   ^^^^^^

	randstring="${str1:$POS:$LEN}"
	# Can parameterize ^^^^ ^^^^

	mkdir -p /home/$username/.icedove/
	mkdir -p /home/$username/.icedove/$randstring.default

	cat << EOF > ./icedoveprofile/profiles.ini
[General]
StartWithLastProfile=1

[Profile0]
Name=default
IsRelative=1
Path=$randstring.default
EOF
cat << EOF > ./icedoveprofile/prefs.js
# Mozilla User Preferences

/* Do not edit this file.
 *
 * If you make changes to this file while the application is running,
 * the changes will be overwritten when the application exits.
 *
 * To make a manual change to preferences, you can visit the URL about:config
 * For more information, see http://www.mozilla.org/unix/customizing.html#prefs
 */

user_pref("app.update.lastUpdateTime.addon-background-update-timer", 1329930989);
user_pref("app.update.lastUpdateTime.blocklist-background-update-timer", 1329931049);
user_pref("extensions.enabledItems", "{972ce4c6-7e08-4474-a285-3208198ce6fd}:3.1.19");
user_pref("extensions.lastAppVersion", "3.1.19");
user_pref("intl.charsetmenu.mailview.cache", "ISO-8859-1");
user_pref("mail.account.account1.identities", "id1");
user_pref("mail.account.account1.server", "server1");
user_pref("mail.account.account2.server", "server2");
user_pref("mail.accountmanager.accounts", "account2,account1");
user_pref("mail.accountmanager.defaultaccount", "account2");
user_pref("mail.accountmanager.localfoldersserver", "server2");
user_pref("mail.append_preconfig_smtpservers.version", 2);
user_pref("mail.attachment.store.version", 1);
user_pref("mail.folder.views.version", 1);
user_pref("mail.identity.id1.archive_folder", "imap://$username%40$domain@$imap/[Gmail]/All Mail");
user_pref("mail.identity.id1.archives_folder_picker_mode", "1");
user_pref("mail.identity.id1.draft_folder", "imap://$username%40$domain@$imap/Drafts");
user_pref("mail.identity.id1.drafts_folder_picker_mode", "0");
user_pref("mail.identity.id1.fcc_folder", "imap://$username%40$domain@$imap/Sent");
user_pref("mail.identity.id1.fcc_folder_picker_mode", "0");
user_pref("mail.identity.id1.fullName", "$fullname");
user_pref("mail.identity.id1.smtpServer", "smtp2");
user_pref("mail.identity.id1.stationery_folder", "imap://$username%40$domain@$imap/Templates");
user_pref("mail.identity.id1.tmpl_folder_picker_mode", "0");
user_pref("mail.identity.id1.useremail", "$emailaddress");
user_pref("mail.identity.id1.valid", true);
user_pref("mail.openMessageBehavior.version", 1);
user_pref("mail.root.imap", "/home/$username/.icedove/$randstring.default/ImapMail");
user_pref("mail.root.imap-rel", "[ProfD]ImapMail");
user_pref("mail.root.none", "/home/$username/.icedove/$randstring.default/Mail");
user_pref("mail.root.none-rel", "[ProfD]Mail");
user_pref("mail.server.server1.capability", 403448357);
user_pref("mail.server.server1.check_new_mail", true);
user_pref("mail.server.server1.directory", "/home/$username/.icedove/$randstring.default/ImapMail/$imap");
user_pref("mail.server.server1.directory-rel", "[ProfD]ImapMail/$imap");
user_pref("mail.server.server1.hostname", "$imap");
user_pref("mail.server.server1.is_gmail", true);
user_pref("mail.server.server1.login_at_startup", true);
user_pref("mail.server.server1.max_cached_connections", 5);
user_pref("mail.server.server1.name", "$emailaddress");
user_pref("mail.server.server1.namespace.personal", "\"\"");
user_pref("mail.server.server1.port", $imapport);
user_pref("mail.server.server1.socketType", 3);
user_pref("mail.server.server1.timeout", 29);
user_pref("mail.server.server1.type", "imap");
user_pref("mail.server.server1.userName", "$username@$domain");
user_pref("mail.server.server2.directory", "/home/$username/.icedove/$randstring.default/Mail/Local Folders");
user_pref("mail.server.server2.directory-rel", "[ProfD]Mail/Local Folders");
user_pref("mail.server.server2.hostname", "Local Folders");
user_pref("mail.server.server2.login_at_startup", true);
user_pref("mail.server.server2.name", "Local Folders");
user_pref("mail.server.server2.type", "none");
user_pref("mail.server.server2.userName", "nobody");
user_pref("mail.smtp.defaultserver", "smtp2");
user_pref("mail.smtpserver.smtp2.authMethod", 3);
user_pref("mail.smtpserver.smtp2.description", "TMX");
user_pref("mail.smtpserver.smtp2.hostname", "$smtp");
user_pref("mail.smtpserver.smtp2.port", $smtpport);
user_pref("mail.smtpserver.smtp2.try_ssl", 3);
user_pref("mail.smtpserver.smtp2.username", "$username@$domain");
user_pref("mail.smtpservers", "smtp2");
user_pref("mail.spam.version", 1);
user_pref("mail.startup.enabledMailCheckOnce", true);
user_pref("mailnews.quotingPrefs.version", 1);
user_pref("mailnews.start_page_override.mstone", "3.1.19");
user_pref("mailnews.tags.$label1.color", "#FF0000");
user_pref("mailnews.tags.$label1.tag", "Important");
user_pref("mailnews.tags.$label2.color", "#FF9900");
user_pref("mailnews.tags.$label2.tag", "Work");
user_pref("mailnews.tags.$label3.color", "#009900");
user_pref("mailnews.tags.$label3.tag", "Personal");
user_pref("mailnews.tags.$label4.color", "#3333FF");
user_pref("mailnews.tags.$label4.tag", "To Do");
user_pref("mailnews.tags.$label5.color", "#993399");
user_pref("mailnews.tags.$label5.tag", "Later");
user_pref("mailnews.tags.version", 2);
user_pref("network.cookie.prefsMigrated", true);
EOF


	cp -pr ./icedoveprofile/* /home/$username/.icedove/$randstring.default
	cp ./icedoveprofile/profiles.ini /home/$username/.icedove
}

main
