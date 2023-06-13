#[derive(Drop)]
struct Ball {
    x: u32,
    y: u32,
    size: u32,
    speed_x: u32,
    speed_y: u32,
    moving_up: bool,
    moving_left: bool
}

#[derive(Drop)]
struct Paddle {
    y: u32,
    size: u32,
    speed: u32,
    moving_up: bool
}

