use option::OptionTrait;
use traits::{Into, TryInto};
use starknet::StorageAccess;

const POW_2_1: u128  = 2;
const POW_2_2: u128  = 4;
const POW_2_17: u128 = 131072;
const POW_2_18: u128 = 262144;
const POW_2_33: u128 = 8589934592;
const POW_2_34: u128 = 17179869184;
const POW_2_50: u128 = 1125899906842624;
const POW_2_66: u128 = 73786976294838206464;

//***********************************************************//
//                            BALL
//***********************************************************//

#[derive(Drop, Copy, Serde, storage_access::StorageAccess)]
struct Ball {
    x: u16,
    y: u16,
    size: u16,
    speed_x: u16,
    speed_y: u16,
    moving_up: bool,
    moving_left: bool
}

impl IntoFelt252BallImpl of Into<Ball, felt252> {
    fn into(self: Ball) -> felt252 {
        let moving_left_value: u128    = if self.moving_left { 1_u128 } else { 0_u128 };
        let moving_up_value: u128      = if self.moving_up   { POW_2_1 } else { 0_u128 };
        let speed_x_value_252: felt252 = self.speed_x.into();
        let speed_x_value: u128        = speed_x_value_252.try_into().unwrap() * POW_2_2;
        let speed_y_value_252: felt252 = self.speed_y.into();
        let speed_y_value: u128        = speed_y_value_252.try_into().unwrap() * POW_2_18;
        let size_value_252: felt252    = self.size.into();       
        let size_value: u128           = size_value_252.try_into().unwrap() * POW_2_34;
        let y_value_252: felt252       = self.y.into();
        let y_value: u128              = y_value_252.try_into().unwrap() * POW_2_50;
        let x_value_252: felt252       = self.x.into();
        let x_value: u128              = x_value_252.try_into().unwrap() * POW_2_66;

        let stored_value: u128 = moving_left_value + moving_up_value + speed_x_value + speed_y_value + size_value + y_value + x_value;
        stored_value.into()
    }
}

//***********************************************************//
//                          PADDLE
//***********************************************************//

#[derive(Drop, Copy, Serde, storage_access::StorageAccess)]
struct Paddle {
    y: u16,
    size: u16,
    speed: u16,
    moving_up: bool
}

impl IntoFelt252PaddleImpl of Into<Paddle, felt252> {
    fn into(self: Paddle) -> felt252 {
        let moving_up_value: u128    = if self.moving_up { 1_u128 } else { 0_u128 };
        let speed_value_252: felt252 = self.speed.into();
        let speed_value: u128        = speed_value_252.try_into().unwrap() * POW_2_1;
        let size_value_252: felt252  = self.size.into();
        let size_value: u128         = size_value_252.try_into().unwrap() * POW_2_17;
        let y_value_252: felt252     = self.y.into();
        let y_value: u128            = y_value_252.try_into().unwrap() * POW_2_33;

        let stored_value: u128 =  moving_up_value + speed_value + size_value + y_value;
        stored_value.into()
    }
}