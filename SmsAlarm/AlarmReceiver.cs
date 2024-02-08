using Android.App;
using Android.Content;
using Android.OS;
using AndroidX.Core.App;
using SmsAlarm;

[BroadcastReceiver(Enabled = true, Label = "Alarm Receiver", Exported =true)]

public class AlarmReceiver : BroadcastReceiver
{
    public override void OnReceive(Context context, Intent intent)
    {
        // Handle the action when the alarm is triggered
        // For example, you can show a notification
        ShowNotification(context);
    }

    private void ShowNotification(Context context)
    {
        // Create notification channel if targeting Android Oreo or higher
        if (Build.VERSION.SdkInt >= BuildVersionCodes.O)
        {
            var channelId = "my_channel_01";
            var channelName = context.GetString(Resource.String.channel_name);
            var importance = NotificationImportance.Default;
            var channel = new NotificationChannel(channelId, channelName, importance);
            var notificationManager = context.GetSystemService(Context.NotificationService) as NotificationManager;
            notificationManager.CreateNotificationChannel(channel);
        }

        // Create notification
        var notification = new NotificationCompat.Builder(context, "my_channel_01")
            .SetContentTitle("Alarm Triggered")
            .SetContentText("This ticket has been assigned to you")
            ///.SetSmallIcon(Resource.Drawable.icn)
            .SetPriority(NotificationCompat.PriorityHigh)
            .SetAutoCancel(true)
            .Build();

        // Show notification
        var notificationManagerCompat = NotificationManagerCompat.From(context);
        notificationManagerCompat.Notify(0, notification);
    }
}
