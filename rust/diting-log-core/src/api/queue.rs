use super::Writer;
use crate::payload::Reader;
use crate::queue::Queue;


fn write_rows(writer: &mut Writer, rows: &[Vec<u8>]) {
    writer.u32(rows.len() as u32);
    for row in rows {
        writer.blob(row);
    }
}

fn read_rows(reader: &mut Reader<'_>) -> Option<Vec<Vec<u8>>> {
    let count = reader.u32()? as usize;
    let mut rows = Vec::with_capacity(count.min(MAX_ROWS_PER_PAYLOAD));
    for _ in 0..count {
        rows.push(reader.blob()?.to_vec());
    }
    Some(rows)
}

const MAX_ROWS_PER_PAYLOAD: usize = 65_536;

pub fn queue_settings(tag: u8) -> Option<crate::queue::Settings> {
    match tag {
        0 => Some(crate::queue::LOG_TABLE),
        1 => Some(crate::queue::HTTP),
        _ => None,
    }
}

pub fn queue_submit(queue: &Queue, payload: &[u8], now_ms: i64) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let row = reader.blob()?.to_vec();
    if !reader.finish() {
        return None;
    }
    Some(submit_answer(queue, queue.submit(row, now_ms)))
}

pub fn queue_submit_many(queue: &Queue, payload: &[u8], now_ms: i64) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let rows = read_rows(&mut reader)?;
    if !reader.finish() {
        return None;
    }
    Some(submit_answer(queue, queue.submit_many(rows, now_ms)))
}

fn submit_answer(queue: &Queue, outcome: Option<crate::queue::Submit>) -> Vec<u8> {
    let mut writer = Writer::new();
    match outcome {
        None => writer.u8(0),
        Some(submit) => {
            writer.u8(1);
            writer.u32(submit.overflow);
            writer.u8(if submit.batch_full { 1 } else { 0 });
            writer.i64(submit.flush_delay_ms(queue.settings()));
        }
    }
    writer.into_vec()
}

pub fn queue_take(queue: &Queue) -> Vec<u8> {
    let mut writer = Writer::new();
    match queue.take() {
        None => writer.u8(0),
        Some(rows) => {
            writer.u8(1);
            write_rows(&mut writer, &rows);
        }
    }
    writer.into_vec()
}

pub fn queue_requeue(queue: &Queue, payload: &[u8]) -> Option<u32> {
    let mut reader = Reader::new(payload);
    let rows = read_rows(&mut reader)?;
    if !reader.finish() {
        return None;
    }
    Some(queue.requeue(rows))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::queue::{HTTP, LOG_TABLE};

    fn row(name: &str) -> Vec<u8> {
        let mut writer = Writer::new();
        writer.string(name);
        writer.into_vec()
    }

    fn submit_payload(name: &str) -> Vec<u8> {
        let mut writer = Writer::new();
        writer.blob(&row(name));
        writer.into_vec()
    }

    #[test]
    fn submit_answers_the_overflow_and_the_flush_delay() {
        let queue = Queue::new(LOG_TABLE);
        let answer = queue_submit(&queue, &submit_payload("first"), 0).unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(reader.u32(), Some(0));
        assert_eq!(reader.u8(), Some(0));
        assert_eq!(reader.i64(), Some(LOG_TABLE.flush_interval_ms));
        assert!(reader.finish());
    }

    #[test]
    fn submit_many_queues_every_row_with_one_answer() {
        let queue = Queue::new(LOG_TABLE);
        let rows: Vec<Vec<u8>> = (0..LOG_TABLE.batch_size)
            .map(|index| row(&index.to_string()))
            .collect();
        let answer = queue_submit_many(&queue, &rows_payload(&rows), 0).unwrap();
        let mut reader = Reader::new(&answer);
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(reader.u32(), Some(0));
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(reader.i64(), Some(0));
        assert!(reader.finish());
        assert_eq!(queue.pending_len(), LOG_TABLE.batch_size as u32);

        let taken = queue_take(&queue);
        let mut reader = Reader::new(&taken);
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(reader.u32(), Some(LOG_TABLE.batch_size as u32));
        let mut blobs = Vec::new();
        for _ in 0..LOG_TABLE.batch_size {
            blobs.push(reader.blob().expect("a row").to_vec());
        }
        assert_eq!(blobs.first().map(Vec::as_slice), Some(&row("0")[..]));
        assert_eq!(
            blobs.last().map(Vec::as_slice),
            Some(&row(&(LOG_TABLE.batch_size - 1).to_string())[..])
        );
    }

    #[test]
    fn submit_many_rejects_drift_and_a_closed_queue() {
        let queue = Queue::new(LOG_TABLE);
        assert_eq!(queue_submit_many(&queue, &[0, 0, 0, 1], 0), None);
        queue.mark_closed();
        let payload = rows_payload(&[row("a")]);
        assert_eq!(queue_submit_many(&queue, &payload, 0), Some(vec![0]));
        assert_eq!(queue.pending_len(), 0);
    }

    fn rows_payload(rows: &[Vec<u8>]) -> Vec<u8> {
        let mut writer = Writer::new();
        writer.u32(rows.len() as u32);
        for row in rows {
            writer.blob(row);
        }
        writer.into_vec()
    }

    #[test]
    fn take_answers_the_rows_and_requeue_takes_them_alone() {
        let queue = Queue::new(HTTP);
        for index in 0..3 {
            queue_submit(&queue, &submit_payload(&index.to_string()), 0).unwrap();
        }
        let taken = queue_take(&queue);
        let mut reader = Reader::new(&taken);
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(reader.u32(), Some(3));
        assert_eq!(reader.blob(), Some(&row("0")[..]));
        assert_eq!(reader.blob(), Some(&row("1")[..]));
        assert_eq!(reader.blob(), Some(&row("2")[..]));
        assert!(reader.finish());

        let mut requeue = Writer::new();
        requeue.u32(3);
        requeue.blob(&row("0"));
        requeue.blob(&row("1"));
        requeue.blob(&row("2"));
        assert_eq!(queue_requeue(&queue, &requeue.into_vec()), Some(0));
        assert_eq!(queue.pending_len(), 3);
        assert_eq!(queue_take(&queue), taken);
    }

    #[test]
    fn an_empty_queue_answers_a_clear_status() {
        let queue = Queue::new(LOG_TABLE);
        assert_eq!(queue_take(&queue), vec![0]);
    }

    #[test]
    fn a_closed_queue_answers_no_acceptance() {
        let queue = Queue::new(LOG_TABLE);
        queue.mark_closed();
        assert_eq!(
            queue_submit(&queue, &submit_payload("row"), 0),
            Some(vec![0])
        );
    }

    #[test]
    fn drift_is_a_failed_decode() {
        let queue = Queue::new(LOG_TABLE);
        assert_eq!(queue_submit(&queue, &[0, 0, 0, 4, 1], 0), None);
        let mut padded = submit_payload("row");
        padded.push(0);
        assert_eq!(queue_submit(&queue, &padded, 0), None);
        assert_eq!(queue_requeue(&queue, &[0, 0, 0, 1]), None);
    }

    #[test]
    fn the_settings_tags_are_the_two_writers() {
        assert_eq!(queue_settings(0), Some(LOG_TABLE));
        assert_eq!(queue_settings(1), Some(HTTP));
        assert_eq!(queue_settings(2), None);
    }
}
