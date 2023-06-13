use option::OptionTrait;
use result::{ResultTrait, ResultTraitImpl};
use traits::{Into, TryInto};
use starknet::{StorageAccess, StorageBaseAddress, SyscallResult};
use starknet::{storage_read_syscall, storage_write_syscall, storage_address_from_base_and_offset};

const POW_2_0: u128 = 1;
const POW_2_1: u128 = 2;
const POW_2_2: u128 = 4;
const POW_2_17: u128 = 131072;
const POW_2_18: u128 = 262144;
const POW_2_25: u128 = 33554432;
const POW_2_35: u128 = 34359738368;
const POW_2_43: u128 = 8796093022208;
const POW_2_59: u128 = 576460752303423488;

#[derive(Drop)]
struct Ball {
    x: u16,
    y: u16,
    size: u8,
    speed_x: u16,
    speed_y: u16,
    moving_up: bool,
    moving_left: bool
}

#[derive(Drop)]
struct Paddle {
    y: u16,
    size: u8,
    speed: u16,
    moving_up: bool
}

impl StorageAccessBallImpl of StorageAccess<Ball> {
    fn write(address_domain: u32, base: StorageBaseAddress, value: Ball) -> SyscallResult<()> {

        //Values
        let moving_left_value: u128 = if value.moving_left { POW_2_0 } else { 0_u128 };
        let moving_up_value: u128   = if value.moving_up   { POW_2_1 } else { 0_u128 };
        let speed_x_value: u128     = value.speed_x.into() * POW_2_2;
        let speed_y_value: u128     = value.speed_y.into() * POW_2_18;
        let size_value: u128        = value.size.into() * POW_2_35;
        let y_value: u128           = value.y.into() * POW_2_43;
        let x_value: u128           = value.x.into() * POW_2_59;

        //Stored value
        let stored_value: u128 = moving_left_value + moving_up_value + speed_x_value + speed_y_value + size_value + y_value + x_value;

        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8), stored_value.into());
        SyscallResult::Ok(())
    }

    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Ball> {
        let value: u128 = storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8))?.try_into().unwrap();
        
        //Values
        let moving_left_value: u128 = (value & 0b1) / POW_2_0;
        let moving_up_value: u128   = (value & 0b10) / POW_2_1;
        let speed_x_value: u128     = (value & 0b111111111111111100) / POW_2_2;
        let speed_y_value: u128     = (value & 0b1111111111111111000000000000000000) / POW_2_18;
        let size_value: u128        = (value & 0b111111110000000000000000000000000000000000) / POW_2_35;
        let y_value: u128           = (value & 0b1111111111111111000000000000000000000000000000000000000000) / POW_2_43;
        let x_value: u128           = (value & 0b11111111111111110000000000000000000000000000000000000000000000000000000000)/ POW_2_59;

        Result::Ok(
            Ball {
                x: x_value.try_into().expect('CANT_READ_X'),
                y: y_value.try_into().expect('CANT_READ_Y'),
                size: size_value.try_into().expect('CANT_READ_SIZE'),
                speed_x: speed_x_value.try_into().expect('CANT_READ_SPEED_X'),
                speed_y: speed_y_value.try_into().expect('CANT_READ_SPEED_Y'),
                moving_up: (moving_up_value > 0_u128),
                moving_left: (moving_left_value > 0_u128)
            }
        )
    }
}

impl StorageAccessPaddleImpl of StorageAccess<Paddle> {
    fn write(address_domain: u32, base: StorageBaseAddress, value: Paddle) -> SyscallResult<()> {

        //Values
        let moving_up_value: u128 = if value.moving_up { POW_2_0 } else { 0_u128 };
        let speed_value: u128     = value.speed.into() * POW_2_1;
        let size_value: u128        = value.size.into() * POW_2_17;
        let y_value: u128           = value.y.into() * POW_2_25;

        //Stored value
        let stored_value: u128 =  moving_up_value + speed_value + size_value + y_value;

        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8), stored_value.into());
        SyscallResult::Ok(())
    }

    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Paddle> {
        let value: u128 = storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8))?.try_into().unwrap();
        
        //Values
        let moving_up_value: u128 = (value & 0b1) / POW_2_0;
        let speed_value: u128     = (value & 0b11111111111111110) / POW_2_1;
        let size_value: u128        = (value & 0b1111111100000000000000000) / POW_2_17;
        let y_value: u128           = (value & 0b11111111111111110000000000000000000000000) / POW_2_25;

        Result::Ok(
            Paddle {
                y: y_value.try_into().expect('CANT_READ_Y'),
                size: size_value.try_into().expect('CANT_READ_SIZE'),
                speed: speed_value.try_into().expect('CANT_READ_SPEED'),
                moving_up: (moving_up_value > 0_u128)
            }
        )
    }
}
