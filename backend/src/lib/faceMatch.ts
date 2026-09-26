/** Similarity (0..1) at or above which the selfie is accepted as the ID holder. */
export const FACE_MATCH_THRESHOLD = 0.8;

/**
 * Compares the selfie against the portrait on the ID and returns a
 * similarity score in 0..1, or null when no face-comparison provider is
 * configured / it couldn't produce a result.
 *
 * No provider is wired up yet, so this always returns null and every
 * submission goes to manual review (FACE_UNVERIFIED). To automate it, call
 * your provider here (e.g. AWS Rekognition CompareFaces or Azure Face) with
 * the two image files and return its similarity / 100.
 */
export async function compareFaces(_idImagePath: string, _selfiePath: string): Promise<number | null> {
  return null;
}
