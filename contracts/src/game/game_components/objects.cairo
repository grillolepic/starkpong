use serde::Serde;
use array::ArrayTrait;
use option::OptionTrait;
use result::{ResultTrait, ResultTraitImpl};
use traits::{Into, TryInto};
use starknet::{StorageAccess, StorageBaseAddress, SyscallResult};
use starknet::{storage_read_syscall, storage_write_syscall, storage_address_from_base_and_offset};

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

#[derive(Drop, Copy, Serde)]
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
        let moving_left_value: u128 = if self.moving_left { 1_u128 } else { 0_u128 };
        let moving_up_value: u128   = if self.moving_up   { POW_2_1 } else { 0_u128 };
        let speed_x_value: u128     = self.speed_x.into() * POW_2_2;
        let speed_y_value: u128     = self.speed_y.into() * POW_2_18;
        let size_value: u128        = self.size.into() * POW_2_34;
        let y_value: u128           = self.y.into() * POW_2_50;
        let x_value: u128           = self.x.into() * POW_2_66;

        let stored_value: u128 = moving_left_value + moving_up_value + speed_x_value + speed_y_value + size_value + y_value + x_value;
        stored_value.into()
    }
}

impl IntoBallFelt252Impl of Into<felt252, Ball> {
    fn into(self: felt252) -> Ball {
        let value: u128 = self.try_into().unwrap();

        let moving_left_value: u128 = (value & 0b1);
        let moving_up_value: u128   = (value & 0b10) / POW_2_1;
        let speed_x_value: u128     = (value & 0b111111111111111100) / POW_2_2;
        let speed_y_value: u128     = (value & 0b1111111111111111000000000000000000) / POW_2_18;
        let size_value: u128        = (value & 0b11111111111111110000000000000000000000000000000000) / POW_2_34;
        let y_value: u128           = (value & 0b111111111111111100000000000000000000000000000000000000000000000000) / POW_2_50;
        let x_value: u128           = (value & 0b1111111111111111000000000000000000000000000000000000000000000000000000000000000000)/ POW_2_66;

        Ball {
            x: x_value.try_into().expect('CANT_READ_X'),
            y: y_value.try_into().expect('CANT_READ_Y'),
            size: size_value.try_into().expect('CANT_READ_SIZE'),
            speed_x: speed_x_value.try_into().expect('CANT_READ_SPEED_X'),
            speed_y: speed_y_value.try_into().expect('CANT_READ_SPEED_Y'),
            moving_up: (moving_up_value > 0_u128),
            moving_left: (moving_left_value > 0_u128)
        }
    }
}

impl StorageAccessBallImpl of StorageAccess<Ball> {
    fn write(address_domain: u32, base: StorageBaseAddress, value: Ball) -> SyscallResult<()> {
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8), value.into());
        SyscallResult::Ok(())
    }

    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Ball> {
        let stored_value = storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8))?;
        SyscallResult::Ok(stored_value.into())
    }
}

//***********************************************************//
//                          PADDLE
//***********************************************************//

#[derive(Drop, Copy, Serde)]
struct Paddle {
    y: u16,
    size: u16,
    speed: u16,
    moving_up: bool
}

impl IntoFelt252PaddleImpl of Into<Paddle, felt252> {
    fn into(self: Paddle) -> felt252 {
        let moving_up_value: u128  = if self.moving_up { 1_u128 } else { 0_u128 };
        let speed_value: u128      = self.speed.into() * POW_2_1;
        let size_value: u128       = self.size.into() * POW_2_17;
        let y_value: u128          = self.y.into() * POW_2_33;

        let stored_value: u128 =  moving_up_value + speed_value + size_value + y_value;
        stored_value.into()
    }
}

impl IntoPaddleFelt252Impl of Into<felt252, Paddle> {
    fn into(self: felt252) -> Paddle {
        let value: u128 = self.try_into().unwrap();

        let moving_up_value: u128   = (value & 0b1);
        let speed_value: u128       = (value & 0b11111111111111110) / POW_2_1;
        let size_value: u128        = (value & 0b111111111111111100000000000000000) / POW_2_17;
        let y_value: u128           = (value & 0b1111111111111111000000000000000000000000000000000) / POW_2_33;

        Paddle {
            y: y_value.try_into().expect('CANT_READ_Y'),
            size: size_value.try_into().expect('CANT_READ_SIZE'),
            speed: speed_value.try_into().expect('CANT_READ_SPEED'),
            moving_up: (moving_up_value > 0_u128)
        }
    }
}

impl StorageAccessPaddleImpl of StorageAccess<Paddle> {
    fn write(address_domain: u32, base: StorageBaseAddress, value: Paddle) -> SyscallResult<()> {
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8), value.into());
        SyscallResult::Ok(())
    }

    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Paddle> {
        let stored_value = storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8))?;
        SyscallResult::Ok(stored_value.into())
    }
}