import { prisma } from '../lib/prisma';
import { sendEmail } from '../lib/email';

/**
 * Creates a server-triggered notification for an async event the
 * recipient might not be looking at the app for (see DriverNotification's
 * doc comment in schema.prisma — CommuterNotification/AdminNotification
 * share the same shape). Fire-and-forget from the caller's perspective —
 * awaited here, but callers should never let a notification failure
 * block the actual mutation that triggered it.
 */
interface NotifyParams {
  title: string;
  message: string;
  /** Lets a client make this notification tappable — see
   * DriverNotification's doc comment in schema.prisma for the
   * type/referenceId convention. Omit both for a notification with
   * nothing to navigate to. */
  type?: string;
  referenceId?: string;
}

export async function notifyDriver(params: NotifyParams & { recipientId: string }) {
  try {
    await prisma.driverNotification.create({
      data: {
        recipientId: params.recipientId,
        title: params.title,
        message: params.message,
        type: params.type ?? null,
        referenceId: params.referenceId ?? null,
      },
    });
  } catch (err) {
    console.error('Failed to create driver notification:', err);
  }
}

export async function notifyCommuter(params: NotifyParams & { recipientId: string }) {
  try {
    await prisma.commuterNotification.create({
      data: {
        recipientId: params.recipientId,
        title: params.title,
        message: params.message,
        type: params.type ?? null,
        referenceId: params.referenceId ?? null,
      },
    });
  } catch (err) {
    console.error('Failed to create commuter notification:', err);
  }

  // Also email it to the commuter's registered address (if they have one).
  // Best-effort and never throws — a mail failure must not affect the
  // request that triggered the notification.
  try {
    const commuter = await prisma.commuter.findUnique({
      where: { id: params.recipientId },
      select: { email: true },
    });
    if (commuter?.email) {
      await sendEmail(
        commuter.email,
        `ManibelApp: ${params.title}`,
        `<p><strong>${escapeHtml(params.title)}</strong></p><p>${escapeHtml(params.message)}</p>` +
          '<p style="color:#888;font-size:12px">You are receiving this because this email is registered to your ManibelApp account.</p>',
      );
    }
  } catch (err) {
    console.error('Failed to email commuter notification:', err);
  }
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/** Broadcasts to every admin — there's no recipientId, admin's a small
 * shared team (see AdminNotification's doc comment in schema.prisma). */
export async function notifyAdmin(params: NotifyParams) {
  try {
    await prisma.adminNotification.create({
      data: {
        title: params.title,
        message: params.message,
        type: params.type ?? null,
        referenceId: params.referenceId ?? null,
      },
    });
  } catch (err) {
    console.error('Failed to create admin notification:', err);
  }
}
