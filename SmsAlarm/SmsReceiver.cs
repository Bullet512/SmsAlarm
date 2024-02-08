using Android.App;
using Android.Content;
using Android.OS;
using Android.Telephony;

[BroadcastReceiver(Enabled = true, Label = "SMS Receiver", Exported =true)]
[IntentFilter(new[] { "android.provider.Telephony.SMS_RECEIVED" })]
public class SmsReceiver : BroadcastReceiver
{
    public override void OnReceive(Context context, Intent intent)
    {
        if (intent.Action.Equals("android.provider.Telephony.SMS_RECEIVED"))
        {
            Bundle bundle = intent.Extras;
            if (bundle != null)
            {
                Java.Lang.Object[] pdus = (Java.Lang.Object[])bundle.Get("pdus");
                if (pdus != null)
                {
                    foreach (Java.Lang.Object pdu in pdus)
                    {
                        SmsMessage sms = SmsMessage.CreateFromPdu((byte[])pdu);
                        string messageBody = sms.MessageBody;
                        string sender = sms.OriginatingAddress; // Retrieve sender information if needed

                        if (messageBody.Contains("this ticket has been assigned to you"))
                        {
                            // Trigger alarm
                            TriggerAlarm(context);
                            break; // Exit the loop once a matching SMS is found
                        }
                    }
                }
            }
        }
    }

    private void TriggerAlarm(Context context)
    {
        // Set up alarm intent
        Intent alarmIntent = new Intent(context, typeof(AlarmReceiver));
        PendingIntent pendingIntent = PendingIntent.GetBroadcast(context, 0, alarmIntent, PendingIntentFlags.UpdateCurrent);

        // Schedule alarm
        AlarmManager alarmManager = (AlarmManager)context.GetSystemService(Context.AlarmService);
        alarmManager.Set(AlarmType.RtcWakeup, Java.Lang.JavaSystem.CurrentTimeMillis(), pendingIntent);
    }
}
